import 'dart:io';
import 'dart:ui' as ui;

import 'package:better_together/domain/invitation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native decoder reads invitation QR', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('二维码识别验证'))));
    final qr = QrPainter(data: 'bettertogether://invite/ABCD23EF', version: QrVersions.auto);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    canvas.translate(32, 32);
    qr.paint(canvas, const Size(448, 448));
    final picture = recorder.endRecording();
    final image = await picture.toImage(512, 512);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final path = '${(await getTemporaryDirectory()).path}/native-invite-qr.png';
    await File(path).writeAsBytes(data!.buffer.asUint8List());
    final scanner = MobileScannerController(autoStart: false);
    final found = await scanner.analyzeImage(path, formats: [BarcodeFormat.qrCode]);
    expect(found?.barcodes.any((b) => invitationToken(b.rawValue ?? '') == 'ABCD23EF'), true);
    await scanner.dispose();
    image.dispose(); picture.dispose();
  });
}
