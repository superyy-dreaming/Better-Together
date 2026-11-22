import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../data/app_repository.dart';
import 'photo_dates.dart';

class PreparedPhoto {
  const PreparedPhoto(
    this.bytes,
    this.filename,
    this.contentType, {
    this.exifOriginal,
    this.exifOffset,
  });
  final Uint8List bytes;
  final String filename, contentType;
  final String? exifOriginal, exifOffset;
}

class AnalysisPhoto {
  const AnalysisPhoto({
    required this.bytes,
    required this.originalSha256,
    required this.width,
    required this.height,
  });
  final Uint8List bytes;
  final String originalSha256;
  final int width, height;
}

const maxAnalysisBytes = 2 * 1024 * 1024;
const maxAnalysisDimension = 1600;

/// The archival bytes are never modified. Decode, orientation, resize, metadata
/// stripping and hashing run off the UI isolate on iOS/Android.
Future<AnalysisPhoto> preparePhotoForRecognition(Uint8List original) =>
    compute(_encodeAnalysisPhoto, original);

AnalysisPhoto _encodeAnalysisPhoto(Uint8List original) {
  final decoded = img.decodeImage(original);
  if (decoded == null) {
    throw const AppException('image_decode', '这张图片无法读取，请换一张照片');
  }
  var oriented = img.bakeOrientation(decoded);
  if (oriented.width > maxAnalysisDimension ||
      oriented.height > maxAnalysisDimension) {
    oriented = img.copyResize(
      oriented,
      width: oriented.width >= oriented.height ? maxAnalysisDimension : null,
      height: oriented.height > oriented.width ? maxAnalysisDimension : null,
      interpolation: img.Interpolation.average,
    );
  }
  // Analysis should contain pixels only. In particular, never forward GPS or
  // the camera's EXIF identity to the selected AI provider.
  oriented.exif.clear();
  oriented.textData?.clear();
  oriented.iccProfile = null;
  var quality = 82;
  var bytes = img.encodeJpg(oriented, quality: quality);
  while (bytes.length > maxAnalysisBytes && quality > 37) {
    quality -= 15;
    bytes = img.encodeJpg(oriented, quality: quality);
  }
  if (bytes.length > maxAnalysisBytes) {
    throw const AppException('analysis_size', '图片压缩后仍超过 2 MB，请换一张');
  }
  return AnalysisPhoto(
    bytes: bytes,
    originalSha256: sha256.convert(original).toString(),
    width: oriented.width,
    height: oriented.height,
  );
}

/// Keep JPEG/PNG bytes and their EXIF intact. image_picker_ios converts HEIC to
/// JPEG while copying source metadata; Android needs an explicit native export.
Future<PreparedPhoto> preparePickedPhoto(String path) async {
  var bytes = await File(path).readAsBytes();
  bool jpeg() =>
      bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff;
  bool png() =>
      bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47;
  if (!jpeg() && !png() && Platform.isAndroid) {
    try {
      final converted = await const MethodChannel('better_together/media')
          .invokeMethod<String>('prepareImage', {'path': path});
      if (converted == null) {
        throw const AppException('image_conversion', '图片无法转换，请换一张');
      }
      final file = File(converted);
      try {
        bytes = await file.readAsBytes();
      } finally {
        if (await file.exists()) await file.delete();
      }
    } on PlatformException {
      throw const AppException('image_conversion', '图片无法转换，请改选 JPEG/PNG 或现在拍摄');
    }
  }
  if (!jpeg() && !png()) {
    throw const AppException('image_format', '请选择 JPEG/PNG 照片，或现在拍摄');
  }
  if (bytes.length > 20 * 1024 * 1024) {
    throw const AppException('image_size', '图片超过 20 MB，请选择较小的照片');
  }
  final date = readOriginalPhotoDate(bytes);
  return PreparedPhoto(
    bytes,
    png() ? 'photo.png' : 'photo.jpg',
    png() ? 'image/png' : 'image/jpeg',
    exifOriginal: date.original,
    exifOffset: date.offset,
  );
}

Future<Uint8List> prepareAvatar(Uint8List bytes) =>
    compute(_encodeAvatar, bytes);
Uint8List _encodeAvatar(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const AppException('avatar_decode', '头像无法读取，请换一张');
  final oriented = img.bakeOrientation(decoded);
  final size = oriented.width < oriented.height
      ? oriented.width
      : oriented.height;
  final crop = img.copyCrop(
    oriented,
    x: (oriented.width - size) ~/ 2,
    y: (oriented.height - size) ~/ 2,
    width: size,
    height: size,
  );
  final avatar = img.copyResize(
    crop,
    width: 512,
    height: 512,
    interpolation: img.Interpolation.average,
  );
  avatar.exif.clear();
  avatar.textData?.clear();
  avatar.iccProfile = null;
  return img.encodeJpg(avatar, quality: 88);
}
