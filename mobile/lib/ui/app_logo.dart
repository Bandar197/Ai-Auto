import 'package:flutter/material.dart';

import '../app.dart' show brandBlue, brandBlueDeep, brandOrange;

/// The "فاحص خارق" (Super Scanner) brand mark, painted as vector (no assets):
/// a blue diagnostic badge with a white car side-silhouette, an orange scan beam
/// sweeping across it, and a small power bolt — "القوة/الخارق". Scales to any size.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 48});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _LogoPainter()),
      );
}

/// Logo + the app name, for headers/app bars.
class AppLogoWordmark extends StatelessWidget {
  const AppLogoWordmark({super.key, this.size = 32, this.title});
  final double size;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final name = title ?? 'فاحص خارق';
    return Row(mainAxisSize: MainAxisSize.min, children: [
      AppLogo(size: size),
      const SizedBox(width: 10),
      Text(name, style: TextStyle(fontSize: size * 0.56, fontWeight: FontWeight.w900, letterSpacing: 0.2)),
    ]);
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    double x(double v) => v * s;

    // Badge: rounded square with a vertical blue gradient.
    final badge = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, s, s), Radius.circular(s * 0.24));
    canvas.drawRRect(
      badge,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [brandBlue, brandBlueDeep],
        ).createShader(Rect.fromLTWH(0, 0, s, s)),
    );

    canvas.save();
    canvas.clipRRect(badge);

    // Car side-silhouette (white), centred.
    final car = Paint()..color = Colors.white;
    final body = Path()
      ..moveTo(x(0.16), x(0.60))
      ..lineTo(x(0.26), x(0.60))
      ..cubicTo(x(0.30), x(0.46), x(0.38), x(0.42), x(0.46), x(0.42))
      ..lineTo(x(0.62), x(0.42))
      ..cubicTo(x(0.70), x(0.42), x(0.74), x(0.48), x(0.80), x(0.54))
      ..lineTo(x(0.84), x(0.58))
      ..cubicTo(x(0.86), x(0.59), x(0.86), x(0.60), x(0.85), x(0.62))
      ..lineTo(x(0.84), x(0.66))
      ..lineTo(x(0.16), x(0.66))
      ..close();
    canvas.drawPath(body, car);

    // Wheels (white tyre, blue hub).
    for (final cx in [0.34, 0.68]) {
      canvas.drawCircle(Offset(x(cx), x(0.66)), x(0.085), car);
      canvas.drawCircle(Offset(x(cx), x(0.66)), x(0.042), Paint()..color = brandBlueDeep);
    }

    // Orange scan beam sweeping across the badge, with soft glow + leading dots.
    final beamY = x(0.30);
    canvas.drawLine(
      Offset(x(0.10), beamY),
      Offset(x(0.90), beamY),
      Paint()
        ..color = brandOrange
        ..strokeWidth = s * 0.045
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      Offset(x(0.10), beamY),
      Offset(x(0.90), beamY),
      Paint()
        ..color = brandOrange.withValues(alpha: 0.35)
        ..strokeWidth = s * 0.11
        ..strokeCap = StrokeCap.round,
    );

    // Power bolt (top-right) — the "خارق" energy.
    final bolt = Path()
      ..moveTo(x(0.60), x(0.10))
      ..lineTo(x(0.50), x(0.26))
      ..lineTo(x(0.58), x(0.26))
      ..lineTo(x(0.50), x(0.40))
      ..lineTo(x(0.72), x(0.21))
      ..lineTo(x(0.62), x(0.21))
      ..lineTo(x(0.70), x(0.10))
      ..close();
    canvas.drawPath(bolt, Paint()..color = brandOrange);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
