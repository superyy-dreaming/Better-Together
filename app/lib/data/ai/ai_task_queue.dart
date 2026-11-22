import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';

import '../../domain/models.dart';
import '../../platform/photo_dates.dart';
import '../../platform/photo_preparation.dart';
import '../app_repository.dart';
import 'device_ai_service.dart';

/// Metadata only: never credentials, images, provider responses or free text.
class AiPendingTask {
  AiPendingTask({
    required this.mediaId,
    required this.owner,
    required this.createdAt,
    this.attempts = 0,
    this.nextAt,
    this.state = 'waiting',
    this.expectedVersion,
    this.photoRevision,
    this.teamId,
    this.bound = false,
    this.requestId,
  });
  final String mediaId, owner, createdAt;
  int attempts;
  DateTime? nextAt;
  String state;
  int? expectedVersion, photoRevision;
  String? teamId, requestId;
  bool bound;
  JsonMap toJson() => {
    'media_id': mediaId,
    'owner': owner,
    'created_at': createdAt,
    'attempts': attempts,
    'next_at': nextAt?.toUtc().toIso8601String(),
    'state': state,
    'expected_version': expectedVersion,
    'photo_revision': photoRevision,
    'team_id': teamId,
    'bound': bound,
    'request_id': requestId,
  };
  factory AiPendingTask.fromJson(JsonMap j) => AiPendingTask(
    mediaId: stringValue(j['media_id']),
    owner: stringValue(j['owner']),
    createdAt: stringValue(j['created_at']),
    attempts: (j['attempts'] as num?)?.toInt() ?? 0,
    nextAt: DateTime.tryParse(stringValue(j['next_at'])),
    state: stringValue(j['state'], 'waiting'),
    expectedVersion: (j['expected_version'] as num?)?.toInt(),
    photoRevision: (j['photo_revision'] as num?)?.toInt(),
    teamId: nullableString(j['team_id']),
    bound: j['bound'] == true,
    requestId: nullableString(j['request_id']),
  );
}

abstract interface class AiTaskStorage {
  Future<List<AiPendingTask>> read(String owner);
  Future<void> write(String owner, List<AiPendingTask> tasks);
}

class FileAiTaskStorage implements AiTaskStorage {
  Future<File> _file(String owner) async {
    final root = await getApplicationSupportDirectory();
    return File(
      '${root.path}/byok-tasks-${sha256.convert(utf8.encode(owner))}.json',
    );
  }

  @override
  Future<List<AiPendingTask>> read(String owner) async {
    final file = await _file(owner);
    if (!await file.exists()) return [];
    final rows = jsonDecode(await file.readAsString());
    if (rows is! List) throw const FormatException('Invalid task metadata');
    return rows
        .map((e) => AiPendingTask.fromJson(jsonObject(e)))
        .where((t) => t.owner == owner && t.mediaId.isNotEmpty)
        .toList();
  }

  @override
  Future<void> write(String owner, List<AiPendingTask> tasks) async {
    final file = await _file(owner);
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.new');
    await temp.writeAsString(
      jsonEncode(tasks.map((t) => t.toJson()).toList()),
      flush: true,
    );
    await temp.rename(file.path);
  }
}

DateTime? nextAiRetry({
  required int attempt,
  required DateTime created,
  required String timezone,
  required DateTime now,
}) {
  if (attempt >= 32) return null;
  final location = tz.getLocation(timezone);
  String day(DateTime value) =>
      tz.TZDateTime.from(value, location).toString().substring(0, 10);
  if (day(created) != day(now)) return null;
  final seconds = (30 * (1 << (attempt - 1).clamp(0, 20))).clamp(30, 1800);
  final next = now.add(Duration(seconds: seconds));
  return day(next) == day(now) ? next : null;
}

/// The app owns archived-photo retries. A paused process persists identities and
/// resumes through fresh authorization; a page never owns or deletes these jobs.
class AiTaskQueue with WidgetsBindingObserver {
  AiTaskQueue({
    required this.ai,
    required this.api,
    required this.currentOwner,
    required this.download,
    AiTaskStorage? storage,
  }) : storage = storage ?? FileAiTaskStorage();
  final DeviceAiService ai;
  final AiBusinessApi api;
  final String? Function() currentOwner;
  final Future<Uint8List> Function(String mediaId) download;
  final AiTaskStorage storage;
  final Map<String, AiPendingTask> _tasks = {};
  final Set<String> _running = {};
  Future<void> _writes = Future.value();
  StreamSubscription<void>? _settings;
  Timer? _timer;
  String? _loadedOwner, _configurationRevision;
  int _epoch = 0;
  bool _active = true, _disposed = false, _started = false;
  final changes = StreamController<void>.broadcast();
  String? issue;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _settings = ai.changes.stream.listen((_) => unawaited(reload()));
    await reload();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _active = false;
      _epoch++;
      _timer?.cancel();
      ai.invalidate();
    } else if (state == AppLifecycleState.resumed) {
      _active = true;
      unawaited(reload());
    }
  }

  Future<void> reload() async {
    if (_disposed) return;
    final epoch = ++_epoch, user = currentOwner();
    _timer?.cancel();
    if (user != _loadedOwner) {
      _tasks.clear();
      _loadedOwner = null;
      if (user != null) {
        try {
          final values = await storage.read(user);
          if (epoch != _epoch || currentOwner() != user) return;
          _tasks.addEntries(values.map((t) => MapEntry(t.mediaId, t)));
          _loadedOwner = user;
          issue = null;
        } catch (_) {
          issue = '待补任务暂不可读，已有打卡保留。可在记录详情补生成。';
        }
      }
    }
    if (user != null) {
      try {
        final configuration = await ai.store.read(user);
        if (epoch != _epoch || user != currentOwner()) return;
        if (configuration.usable &&
            configuration.settings.revision != _configurationRevision) {
          for (final task in _tasks.values) {
            if (task.state == 'needs_configuration') {
              task.state = 'waiting';
              task.nextAt = null;
            }
          }
        }
        _configurationRevision = configuration.settings.revision;
      } catch (_) {
        issue = '设备安全存储暂不可读，打卡保留，可解锁后补生成。';
      }
    }
    _emit();
    _pump();
  }

  void _emit() {
    if (!changes.isClosed) changes.add(null);
  }

  Future<void> _persist() {
    final user = _loadedOwner;
    if (user == null) return Future.value();
    final copy = _tasks.values
        .map((t) => AiPendingTask.fromJson(t.toJson()))
        .toList();
    _writes = _writes.then((_) => storage.write(user, copy)).catchError((
      Object _,
    ) {
      issue = '待补任务尚未保存到本机。打卡已保留，可在详情主动补生成。';
      _emit();
    });
    return _writes;
  }

  Future<void> enqueue(String mediaId, {bool manual = false}) async {
    final user = currentOwner();
    if (user == null) return;
    if (user != _loadedOwner) await reload();
    if (user != currentOwner() || user != _loadedOwner) return;
    final task = _tasks.putIfAbsent(
      mediaId,
      () => AiPendingTask(
        mediaId: mediaId,
        owner: user,
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ),
    );
    if (manual) {
      task.state = 'manual';
      task.nextAt = null;
      task.bound = false;
      task.requestId = null;
      task.attempts = 0;
    }
    await _persist();
    _pump();
  }

  void wake() => _pump();
  void _pump() {
    if (!_started || _disposed || !_active || currentOwner() != _loadedOwner) {
      return;
    }
    _timer?.cancel();
    for (final task in _tasks.values.toList()) {
      if (_running.contains(task.mediaId) ||
          !['waiting', 'manual', 'retry'].contains(task.state)) {
        continue;
      }
      if (task.nextAt != null && task.nextAt!.isAfter(DateTime.now())) continue;
      _running.add(task.mediaId);
      unawaited(
        _run(task, _epoch).whenComplete(() {
          _running.remove(task.mediaId);
          if (!_disposed && _active) _schedule();
        }),
      );
    }
    _schedule();
  }

  void _schedule() {
    if (_disposed || !_active) return;
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 5), _pump);
  }

  void _check(AiPendingTask task, int epoch) {
    if (_disposed ||
        !_active ||
        epoch != _epoch ||
        task.owner != currentOwner()) {
      throw const AppException('ai_cancelled', '任务暂停');
    }
  }

  Future<void> _run(AiPendingTask task, int epoch) async {
    String timezone = 'UTC';
    DateTime created = DateTime.tryParse(task.createdAt) ?? DateTime.now();
    try {
      _check(task, epoch);
      final context = jsonObject(
        await api('ai_context', args: {'media_id': task.mediaId}),
      );
      _check(task, epoch);
      if (context['awaiting_confirmation'] == true) {
        task.nextAt = DateTime.now().add(const Duration(seconds: 30));
        // Unconfirmed archives remain recoverable without endlessly polling.
        if (DateTime.now().difference(created) > const Duration(days: 1)) {
          task.state = 'awaiting_confirmation';
        }
        return;
      }
      timezone = stringValue(context['timezone'], 'UTC');
      created =
          DateTime.tryParse(stringValue(context['created_at'])) ?? created;
      final previous = jsonObject(context['result']);
      if (previous['status'] == 'ready' || previous['status'] == 'rejected') {
        task.state = 'complete';
        return;
      }
      final manual = task.state == 'manual';
      if (!manual &&
          nextAiRetry(
                attempt: task.attempts,
                created: created,
                timezone: timezone,
                now: DateTime.now(),
              ) ==
              null) {
        task.state = 'expired';
        return;
      }
      if (!task.bound) {
        task.expectedVersion = (context['record_version'] as num).toInt();
        task.photoRevision = (context['photo_revision'] as num).toInt();
        task.teamId = nullableString(context['scope_team_id']);
        task.bound = true;
        task.requestId = const Uuid().v4();
        await _persist();
      } else if (task.expectedVersion != context['record_version'] ||
          task.photoRevision != context['photo_revision'] ||
          task.teamId != nullableString(context['scope_team_id'])) {
        task.state = 'changed';
        return;
      }
      final config = await ai.store.read(task.owner);
      _check(task, epoch);
      if (!config.usable) {
        task.state = 'needs_configuration';
        return;
      }
      task.attempts++;
      final existing = ai.pendingRecognition(task.mediaId);
      PhotoRecognition result;
      if (existing != null) {
        result = await existing;
      } else {
        final original = await download(task.mediaId);
        _check(task, epoch);
        final exif = readOriginalPhotoDate(original);
        final analysis = await preparePhotoForRecognition(original);
        _check(task, epoch);
        result = await ai.recognize(
          PhotoRecognitionRequest(
            analysisBytes: analysis.bytes,
            photoId: task.mediaId,
            batchId: stringValue(context['batch_id']),
            source: stringValue(context['source']),
            originalSha256: analysis.originalSha256,
            exifOriginal: exif.original,
            exifOffset: exif.offset,
            archivedMediaId: task.mediaId,
          ),
        );
      }
      _check(task, epoch);
      if (result.isPending) {
        if ([
          'ai_not_configured',
          'ai_key_invalid',
          'ai_format_unsupported',
          'ai_invalid_schema',
          'ai_invalid_json',
        ].contains(result.errorCode)) {
          task.state = 'needs_configuration';
        } else {
          task.nextAt = nextAiRetry(
            attempt: task.attempts,
            created: created,
            timezone: timezone,
            now: DateTime.now(),
          );
          task.state = task.nextAt == null ? 'expired' : 'retry';
        }
        return;
      }
      final saved = jsonObject(
        await api(
          'save_byok_photo',
          args: {
            'media_id': task.mediaId,
            'expected_version': task.expectedVersion,
            'expected_photo_revision': task.photoRevision,
            'scope_team_id': task.teamId,
            'idempotency_key': task.requestId,
            'result': result.toJson(),
          },
        ),
      );
      _check(task, epoch);
      task.state = saved['applied'] == true ? 'complete' : 'changed';
    } on AppException catch (e) {
      if (e.code == 'ai_cancelled') return;
      if (['42501', 'forbidden', 'FORBIDDEN', 'NOT_FOUND'].contains(e.code)) {
        task.state = 'unavailable';
      } else {
        task.nextAt = nextAiRetry(
          attempt: task.attempts + 1,
          created: created,
          timezone: timezone,
          now: DateTime.now(),
        );
        task.state = task.nextAt == null ? 'expired' : 'retry';
      }
    } catch (_) {
      task.nextAt = nextAiRetry(
        attempt: task.attempts + 1,
        created: created,
        timezone: timezone,
        now: DateTime.now(),
      );
      task.state = task.nextAt == null ? 'expired' : 'retry';
    } finally {
      if (task.owner == _loadedOwner && !_disposed) {
        await _persist();
        _emit();
      }
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _epoch++;
    _timer?.cancel();
    if (_started) WidgetsBinding.instance.removeObserver(this);
    await _settings?.cancel();
    await _writes;
    await changes.close();
  }
}
