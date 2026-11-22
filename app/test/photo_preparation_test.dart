import 'dart:typed_data';

import 'package:better_together/platform/photo_preparation.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'analysis is bounded JPEG while original bytes and digest are preserved',
    () async {
      final source = img.Image(width: 2400, height: 1800);
      source.exif.imageIfd.orientation = 6;
      source.exif.imageIfd['Make'] = 'Private Camera';
      final original = img.encodeJpg(source, quality: 90);
      final before = Uint8List.fromList(original);
      final analysis = await preparePhotoForRecognition(original);
      expect(original, before);
      expect(analysis.originalSha256, sha256.convert(original).toString());
      expect(analysis.bytes.length, lessThanOrEqualTo(maxAnalysisBytes));
      expect(analysis.width, 1200);
      expect(analysis.height, 1600);
      expect(analysis.bytes.take(3), [0xff, 0xd8, 0xff]);
      final decoded = img.decodeJpg(analysis.bytes)!;
      expect(decoded.width, 1200);
      expect(decoded.height, 1600);
      expect(decoded.exif.imageIfd['Make'], isNull);
    },
  );

  test('avatar is square JPEG with orientation corrected and metadata removed', () async {
    final source=img.Image(width:900,height:600); source.exif.imageIfd.orientation=6;source.exif.imageIfd['Make']='private';
    final bytes=await prepareAvatar(img.encodeJpg(source)); final avatar=img.decodeJpg(bytes)!;
    expect(avatar.width,512);expect(avatar.height,512);expect(avatar.exif.imageIfd['Make'],isNull);
  });

  test('small PNG is encoded as JPEG without enlarging dimensions', () async {
    final original = img.encodePng(img.Image(width: 600, height: 400));
    final analysis = await preparePhotoForRecognition(original);
    expect(analysis.width, 600);
    expect(analysis.height, 400);
    expect(img.decodeJpg(analysis.bytes), isNotNull);
  });
}
