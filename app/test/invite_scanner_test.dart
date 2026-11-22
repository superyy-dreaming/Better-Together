import 'dart:async';

import 'package:better_together/features/team/invite_scanner_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class FakeScanner extends MobileScannerPlatform {
  final captures = StreamController<BarcodeCapture>.broadcast();
  int starts = 0, stops = 0, disposals = 0;
  bool denied = false;
  @override
  Stream<BarcodeCapture?> get barcodesStream => captures.stream;
  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();
  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();
  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) async {
    starts++;
    if (denied) {
      throw const MobileScannerException(
        errorCode: MobileScannerErrorCode.permissionDenied,
      );
    }
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.unavailable,
      size: Size(320, 320),
    );
  }

  @override
  Widget buildCameraView() => const ColoredBox(color: Colors.black);
  @override
  Future<void> stop({bool force = false}) async {
    stops++;
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }
}

void main() {
  Future<FakeScanner> mount(WidgetTester tester, {bool denied = false}) async {
    tester.view.physicalSize = const Size(375, 950);
    tester.view.devicePixelRatio = 1;
    final original = MobileScannerPlatform.instance;
    final scanner = FakeScanner()..denied = denied;
    MobileScannerPlatform.instance = scanner;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      MobileScannerPlatform.instance = original;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await scanner.captures.close();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final code = await Navigator.of(context).push<String>(
                  MaterialPageRoute(builder: (_) => const InviteScannerPage()),
                );
                if (context.mounted && code != null) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(code)));
                }
              },
              child: const Text('打开扫码'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开扫码'));
    await tester.pumpAndSettle();
    return scanner;
  }

  testWidgets(
    'invalid QR stays open, valid repeated detection returns once and stops camera',
    (tester) async {
      final scanner = await mount(tester);
      scanner.captures.add(
        const BarcodeCapture(
          barcodes: [Barcode(rawValue: 'https://unrelated.example')],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('这不是小队邀请码'), findsOneWidget);
      const valid = BarcodeCapture(
        barcodes: [Barcode(rawValue: 'bettertogether://invite/ABCD23EF')],
      );
      scanner.captures.add(valid);
      scanner.captures.add(valid);
      await tester.pumpAndSettle();
      expect(find.byType(InviteScannerPage), findsNothing);
      expect(find.text('ABCD23EF'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(scanner.stops + scanner.disposals, greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('denied camera keeps manual exit available', (tester) async {
    await mount(tester, denied: true);
    expect(find.textContaining('未获得相机权限'), findsOneWidget);
    await tester.ensureVisible(find.text('改为输入邀请码'));
    await tester.tap(find.text('改为输入邀请码'));
    await tester.pumpAndSettle();
    expect(find.byType(InviteScannerPage), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
