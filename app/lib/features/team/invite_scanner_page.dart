import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../domain/invitation.dart';
import '../../ui/design.dart';

final inviteScannerProvider = Provider<Future<String?> Function(BuildContext)>(
  (ref) =>
      (context) => Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const InviteScannerPage()),
      ),
);

class InviteScannerPage extends StatefulWidget {
  const InviteScannerPage({super.key});

  @override
  State<InviteScannerPage> createState() => _InviteScannerPageState();
}

class _InviteScannerPageState extends State<InviteScannerPage>
    with WidgetsBindingObserver {
  bool completed = false;
  final camera = MobileScannerController(formats: const [BarcodeFormat.qrCode]);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> resumeCamera() async {
    try {
      await camera.start();
    } on MobileScannerException {
      // The controller exposes the error to the visible errorBuilder.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (completed || !camera.value.hasCameraPermission) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(resumeCamera());
    } else {
      unawaited(camera.stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(camera.dispose());
    super.dispose();
  }

  String? issue;

  Future<void> detected(BarcodeCapture capture) async {
    if (completed || !mounted) return;
    for (final barcode in capture.barcodes) {
      final token = invitationToken(barcode.rawValue ?? '');
      if (token == null) continue;
      completed = true;
      await camera.stop();
      if (mounted) Navigator.of(context).pop(token);
      return;
    }
    if (issue == null) {
      setState(() => issue = '这不是小队邀请码，请扫描队友在 Better Together 中生成的二维码。');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('扫码加入小队')),
    body: PageBody(
      children: [
        const Text('对准队友的小队邀请二维码'),
        const SizedBox(height: 16),
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: MobileScanner(
              controller: camera,
              onDetect: detected,
              placeholderBuilder: (_) =>
                  const Center(child: CircularProgressIndicator.adaptive()),
              errorBuilder: (context, error) => ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        error.errorCode ==
                                MobileScannerErrorCode.permissionDenied
                            ? '未获得相机权限。可在系统设置中允许 Better Together 使用相机，或返回手动输入邀请码。'
                            : '相机暂时不可用。请重试，或返回手动输入邀请码。',
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: resumeCamera,
                        child: const Text('重试相机'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Semantics(
          liveRegion: true,
          child: Text(issue ?? '识别后会返回加入页面，确认后才会加入小队。'),
        ),
        const SizedBox(height: 20),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('改为输入邀请码'),
        ),
      ],
    ),
  );
}
