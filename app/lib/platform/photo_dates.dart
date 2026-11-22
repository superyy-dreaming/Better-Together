import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:timezone/timezone.dart' as tz;

/// Header-only EXIF read. No original pixels are recompressed or rewritten.
({String? original, String? offset}) readOriginalPhotoDate(Uint8List bytes) {
  try {
    img.ExifData? exif;
    if (bytes.length > 3 && bytes[0] == 255 && bytes[1] == 216) {
      exif = img.decodeJpgExif(bytes);
    } else if (bytes.length > 8 && bytes[0] == 137 && bytes[1] == 80) {
      final data = ByteData.sublistView(bytes);
      var pos = 8;
      while (pos + 12 <= bytes.length) {
        final length = data.getUint32(pos);
        if (length > bytes.length - pos - 12) break;
        final type = String.fromCharCodes(bytes.sublist(pos + 4, pos + 8));
        if (type == 'eXIf') {
          exif = img.ExifData.fromInputBuffer(
            img.InputBuffer(bytes.sublist(pos + 8, pos + 8 + length)),
          );
          break;
        }
        pos += length + 12;
      }
    }
    return (
      original: exif?.exifIfd[0x9003]?.toString(),
      offset: exif?.exifIfd[0x9011]?.toString(),
    );
  } catch (_) {
    return (original: null, offset: null);
  }
}

String? photoCalendarDate(String? original, String? offset, String timezone) {
  if (original == null) return null;
  final m = RegExp(r'^(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})')
      .firstMatch(original);
  if (m == null) return null;
  try {
    final values = [for (var i = 1; i <= 6; i++) int.parse(m[i]!)];
    final location = tz.getLocation(timezone);
    final zone = offset != null && RegExp(r'^[+-]\d{2}:\d{2}$').hasMatch(offset)
        ? offset
        : null;
    final value = zone == null
        ? tz.TZDateTime(
            location,
            values[0],
            values[1],
            values[2],
            values[3],
            values[4],
            values[5],
          )
        : tz.TZDateTime.from(
            DateTime.parse(
              '${m[1]}-${m[2]}-${m[3]}T${m[4]}:${m[5]}:${m[6]}$zone',
            ),
            location,
          );
    // Reject invalid civil dates rather than DateTime's silent normalization.
    final civil = DateTime(
      values[0],
      values[1],
      values[2],
      values[3],
      values[4],
      values[5],
    );
    if (civil.year != values[0] ||
        civil.month != values[1] ||
        civil.day != values[2] ||
        values[3] > 23 ||
        values[4] > 59 ||
        values[5] > 59) {
      return null;
    }
    return '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  } catch (_) {
    return null;
  }
}
