// Dedicated Release entry point. Never reads or changes the user's persistent
// Supabase session. Login credentials are supplied in a private container file,
// read once, then removed. No provider key is accepted by this baseline runner.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:material_ui/material_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:better_together/data/app_controller.dart';
import 'package:better_together/features/settings/ai_settings_page.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:better_together/data/ai_timing.dart';
import 'package:better_together/data/app_repository.dart';
import 'package:better_together/data/supabase_repository.dart';
import 'package:better_together/domain/models.dart';
import 'package:better_together/features/checkin/checkin_draft.dart';
import 'package:better_together/features/checkin/recognition_card.dart';
import 'package:better_together/platform/photo_preparation.dart';
import 'package:better_together/ui/design.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  AiTiming.enabled = true;
  runApp(
    MaterialApp(
      theme: buildTheme(Brightness.light),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh', 'CN')],
      locale: const Locale('zh', 'CN'),
      home: const BenchmarkPage(),
    ),
  );
}

class BenchmarkPage extends StatefulWidget {
  const BenchmarkPage({super.key});
  @override
  State<BenchmarkPage> createState() => _BenchmarkPageState();
}

class _BenchmarkPageState extends State<BenchmarkPage>
    with WidgetsBindingObserver {
  JsonMap configurationEvidence = {};
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    AiTiming.mark('app_lifecycle', state: state.name);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  CheckinDraft? draft;
  List<Plan> plans = [];
  SupabaseAppRepository? configurationRepository;
  Completer<void>? startGate;
  String? settingsIssue;
  Future<void> configure() async {
    final repository = configurationRepository;
    if (repository == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProviderScope(
          overrides: [repositoryProvider.overrideWithValue(repository)],
          child: const AiSettingsPage(),
        ),
      ),
    );
  }

  Future<void> begin() async {
    final repository = configurationRepository;
    if (repository == null || startGate == null || startGate!.isCompleted) {
      return;
    }
    final settings = jsonObject(await repository.action('get_ai_settings'));
    if (settings['enabled'] != true || settings['has_key'] != true) {
      setState(() => settingsIssue = '请先在 AI 设置中测试并保存本次合成测试的配置。');
      return;
    }
    setState(() => settingsIssue = null);
    startGate!.complete();
  }

  String progress = '准备合成基准测试';
  final List<JsonMap> results = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(run()));
  }

  void changed() {
    if (mounted) setState(() {});
  }

  Future<void> persist(Directory directory, String stage, String state) async {
    final file = File('${directory.path}/ai-benchmark-result.json');
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'stage': stage,
        'state': state,
        'platform': Platform.operatingSystem,
        'mode': 'release',
        'configuration': configurationEvidence,
        'runs': results,
      }),
      flush: true,
    );
    await temporary.rename(file.path);
  }

  Future<void> run() async {
    final documents = await getApplicationDocumentsDirectory();
    final folder = Directory('${documents.path}/ai-benchmark');
    var stage = 'unknown';
    try {
      final inputFile = File('${folder.path}/input.json');
      final input = jsonObject(jsonDecode(await inputFile.readAsString()));
      // Retain only the private synthetic-account manifest until the run ends.
      stage = input['stage'] as String;
      final runs = jsonList(input['runs']);
      await persist(documents, stage, 'starting');
      if (input['byok'] == true) {
        final first = jsonObject(runs.first);
        final client = SupabaseClient(
          input['url'] as String,
          input['anon'] as String,
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        );
        await client.auth.signInWithPassword(
          email: first['email'] as String,
          password: first['password'] as String,
        );
        configurationRepository = SupabaseAppRepository(
          client,
          supabaseUrl: input['url'] as String,
          anonKey: input['anon'] as String,
        );
        final settings = jsonObject(
          await configurationRepository!.action('get_ai_settings'),
        );
        configurationEvidence = {
          'model_sha256': sha256
              .convert(utf8.encode(stringValue(settings['model'])))
              .toString(),
          'endpoint_sha256': sha256
              .convert(utf8.encode(stringValue(settings['base_url'])))
              .toString(),
          'model_matches_example':
              settings['model'] == 'deepseek-ai/DeepSeek-V4.1-Flash',
          'endpoint_matches_example':
              settings['base_url'] == 'https://api.siliconflow.cn/v1',
          'format': settings['format'],
        };
        startGate = Completer<void>();
        progress = '请配置合成测试账号的 AI';
        changed();
        await persist(documents, stage, 'awaiting_configuration');
        if (input['auto_start'] == true &&
            settings['enabled'] == true &&
            settings['has_key'] == true) {
          startGate!.complete();
        }
        await startGate!.future;
        await configurationRepository!.dispose();
        await client.dispose();
        configurationRepository = null;
        startGate = null;
      }
      for (var index = 0; index < runs.length; index++) {
        final run = jsonObject(runs[index]);
        AiTiming.reset();
        progress = '${index + 1}/${runs.length} · ${run['scenario']}';
        changed();
        // SupabaseClient, deliberately not Supabase.initialize: memory only.
        final client = SupabaseClient(
          input['url'] as String,
          input['anon'] as String,
        );
        final repository = SupabaseAppRepository(
          client,
          supabaseUrl: input['url'] as String,
          anonKey: input['anon'] as String,
        );
        final result = <String, Object?>{
          'scenario': run['scenario'],
          'repeat': run['repeat'],
          'started_at': DateTime.now().toUtc().toIso8601String(),
          'stamp': 'not_attempted',
        };
        try {
          await client.auth.signInWithPassword(
            email: run['email'] as String,
            password: run['password'] as String,
          );
          var snapshot = await repository.bootstrap();
          if (input['byok'] == true) {
            if (snapshot.team != null) {
              if (!snapshot.team!.name.startsWith('AI 合成基准 ') ||
                  snapshot.team!.members.length != 1) {
                throw const AppException(
                  'BENCHMARK_SCOPE_INVALID',
                  '合成范围检查未通过',
                );
              }
              await repository.action(
                'manage_team',
                args: {'operation': 'dissolve'},
              );
            }
            await repository.action(
              'create_team',
              args: {
                'name': 'AI 合成基准 $stage ${index + 1}',
                'timezone': 'Asia/Shanghai',
              },
            );
            snapshot = await repository.bootstrap();
          }
          plans = snapshot.plans;
          if (input['byok'] == true) {
            final candidates = jsonObject(
              await repository.action('ai_context'),
            )['plans'];
            if (candidates is! List ||
                candidates.length != 2 ||
                candidates.any(
                  (p) => p is! Map<String, Object?> || p['id'] is! String,
                )) {
              throw const AppException(
                'BENCHMARK_CANDIDATES_INVALID',
                '合成测试候选计划结构不符',
              );
            }
            result['candidate_count'] = candidates.length;
            result['candidate_categories'] = candidates
                .map((p) => jsonObject(p)['category'])
                .toList();
          }
          final current = CheckinDraft(repository: repository)
            ..addListener(changed);
          draft = current;
          final files = jsonList(run['files']);
          AiTiming.reset();
          AiTiming.selectionStarted(current.batchId, files.length);
          final work = <Future<void>>[];
          // Same as the picker callback: sequential original reads, asynchronous
          // draft.add, current production compression and recognition routing.
          for (final name in files) {
            AiTiming.mark('original_read_start', batch: current.batchId);
            final original = await preparePickedPhoto('${folder.path}/$name');
            AiTiming.mark(
              'original_read_end',
              batch: current.batchId,
              bytes: original.bytes.length,
            );
            work.add(current.add(original, run['source'] as String));
          }
          AiTiming.selectionEnded(current.batchId);
          await Future.wait(work);
          // Flush the same RecognitionCard's post-frame visibility observation.
          changed();
          await WidgetsBinding.instance.endOfFrame;
          result['photos'] = [
            for (final photo in current.photos)
              {
                'id': photo.id,
                'state': photo.phase.name,
                'original_bytes': photo.original.bytes.length,
                'analysis_bytes': photo.analysis?.bytes.length,
                'plan_id': photo.recognition?.planId,
                'confidence': photo.recognition?.confidence,
                'summary': photo.recognition?.summary,
                'fields': photo.recognition?.fields
                    .map((f) => f.toJson())
                    .toList(),
                'screenshot_date': photo.recognition?.screenshotDate,
              },
          ];
          if (current.canConfirm) {
            final ids = await current.archiveConfirmed();
            result['archived'] = ids.length;
            result['archive_errors'] = [
              for (final photo in current.photos)
                if (photo.uploadError != null)
                  {'id': photo.id, 'message': photo.uploadError},
            ];
            if (ids.isNotEmpty) {
              AiTiming.mark('stamp_start', batch: current.batchId);
              final response = jsonObject(
                await repository.action(
                  'submit_checkin',
                  args: {
                    'media_ids': ids,
                    'note': '',
                    'idempotency_key': const Uuid().v4(),
                    'response_version': 2,
                  },
                ),
              );
              AiTiming.mark('stamp_end', batch: current.batchId);
              result['stamp'] = 'saved';
              result['checkin_ids'] = response['checkin_ids'];
            }
          }
        } catch (error) {
          // Do not emit exception text: SDK/provider bodies can contain secrets.
          if (AiTiming.events.any((e) => e['event'] == 'stamp_start') &&
              !AiTiming.events.any((e) => e['event'] == 'stamp_end')) {
            AiTiming.mark('stamp_unconfirmed', batch: draft?.batchId);
          }
          result['error'] =
              error is AppException &&
                  RegExp(r'^[A-Za-z0-9_]{1,64}$').hasMatch(error.code)
              ? error.code
              : 'BENCHMARK_RUN_FAILED';
        } finally {
          result['events'] = List<JsonMap>.from(AiTiming.events);
          results.add(result);
          await persist(documents, stage, 'running');
          draft?.removeListener(changed);
          draft?.dispose();
          draft = null;
          await repository.dispose();
          await client.dispose();
          changed();
        }
      }
      await persist(documents, stage, 'complete');
      await inputFile.delete();
      progress = '合成基准测试完成，共 ${results.length} 次';
    } catch (_) {
      progress = '测试暂停：请检查本机测试清单';
      await persist(documents, stage, 'harness_error');
    }
    changed();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AI 合成基准测试')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(progress, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),
            if (configurationRepository != null) ...[
              const Text(
                '只用固定合成图片和专用测试账号。正式账号登录与数据保持原样。密钥仅存本机测试账号，不会复制旧服务器密钥。',
              ),
              FilledButton(onPressed: configure, child: const Text('打开 AI 设置')),
              OutlinedButton(
                onPressed: begin,
                child: const Text('配置已保存，开始 20 次测试'),
              ),
              if (settingsIssue != null) Text(settingsIssue!),
            ],
            // Eagerly build cards like the existing confirmation page. Visibility
            // means rendered in that page, not that a below-fold card was scrolled to.
            for (final photo in draft?.photos ?? <DraftPhoto>[]) ...[
              RecognitionCard(photo: photo, plans: plans),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    ),
  );
}
