import 'package:material_ui/material_ui.dart';

String bearPreset(int index) =>
    'preset:bear-${(index % 12 + 1).toString().padLeft(2, '0')}';
int bearIndex(String identity) =>
    identity.codeUnits.fold<int>(0, (h, c) => (h * 31 + c) & 0x7fffffff) % 12;

/// Original illustrated avatar assets, drawn at display resolution.
class BearAvatar extends StatelessWidget {
  const BearAvatar({super.key, required this.index, this.size = 44});
  final int index;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _BearPainter(index % 12)),
  );
}

class _BearPainter extends CustomPainter {
  const _BearPainter(this.index);
  final int index;
  static const fur = [
    0xffbc8559,
    0xfff5e6c8,
    0xffb6caa6,
    0xffc8b7df,
    0xffe4ac91,
    0xff99bed1,
    0xffca9a6d,
    0xffdad6cd,
    0xffd7b77f,
    0xffa8c0b9,
    0xffd7a5b4,
    0xffb4b5d7,
  ];
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 100);
    final fill = Paint()..color = Color(fur[index]);
    final ink = Paint()..color = const Color(0xff332b29);
    canvas.drawCircle(
      const Offset(50, 50),
      50,
      Paint()..color = Color(fur[index]).withValues(alpha: .22),
    );
    canvas.drawCircle(const Offset(25, 28), 16, fill);
    canvas.drawCircle(const Offset(75, 28), 16, fill);
    final blush = Paint()..color = const Color(0xffe8b0a0);
    canvas.drawCircle(const Offset(25, 28), 8, blush);
    canvas.drawCircle(const Offset(75, 28), 8, blush);
    canvas.drawOval(const Rect.fromLTWH(15, 24, 70, 64), fill);
    canvas.drawOval(
      const Rect.fromLTWH(32, 52, 36, 29),
      Paint()..color = const Color(0xffffefd5),
    );
    canvas.drawOval(const Rect.fromLTWH(33, 45, 5, 7), ink);
    canvas.drawOval(const Rect.fromLTWH(62, 45, 5, 7), ink);
    canvas.drawOval(const Rect.fromLTWH(44, 57, 12, 8), ink);
    final smile = Path()
      ..moveTo(50, 64)
      ..lineTo(50, 69)
      ..quadraticBezierTo(43, 75, 41, 68)
      ..moveTo(50, 69)
      ..quadraticBezierTo(57, 75, 59, 68);
    canvas.drawPath(
      smile,
      Paint()
        ..color = ink.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawOval(const Rect.fromLTWH(23, 56, 11, 6), blush);
    canvas.drawOval(const Rect.fromLTWH(66, 56, 11, 6), blush);
    final accent = Paint()
      ..color = [
        const Color(0xff326455),
        const Color(0xffbd554a),
        const Color(0xff617da5),
      ][index % 3];
    if (index % 3 == 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(25, 79, 50, 10),
          const Radius.circular(5),
        ),
        accent,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(60, 84, 10, 14),
          const Radius.circular(3),
        ),
        accent,
      );
    } else if (index % 3 == 1) {
      canvas.drawOval(const Rect.fromLTWH(57, 20, 22, 9), accent);
      canvas.drawCircle(const Offset(68, 18), 9, accent);
    } else {
      canvas.drawCircle(
        const Offset(36, 49),
        11,
        Paint()
          ..color = accent.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      canvas.drawCircle(
        const Offset(64, 49),
        11,
        Paint()
          ..color = accent.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      canvas.drawLine(
        const Offset(47, 49),
        const Offset(53, 49),
        Paint()
          ..color = accent.color
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_BearPainter oldDelegate) => oldDelegate.index != index;
}
