import 'dart:math' as math;
import 'dart:ui';

import 'package:design_system/design_system.dart';

/// The eleven fruits, drawn once each into a [Picture] at a unit radius of
/// 100 and replayed scaled every frame.
///
/// A pile of sixty fruits rebuilding their leaves and seeds as paths every
/// frame is measurable on a mid-range phone; replaying a recorded picture is
/// not.
class FruitArt {
  FruitArt._();

  static final FruitArt instance = FruitArt._();

  static const List<({String name, Color fill, Color deep})> palette =
      <({String name, Color fill, Color deep})>[
    (name: 'Blueberry', fill: Color(0xFF4A86E8), deep: Color(0xFF2B5CB8)),
    (name: 'Strawberry', fill: Color(0xFFEF3E45), deep: Color(0xFFB8232B)),
    (name: 'Raspberry', fill: Color(0xFFE0336B), deep: Color(0xFFA8194A)),
    (name: 'Peach', fill: Color(0xFFFFA48A), deep: Color(0xFFE07A62)),
    (name: 'Lemon', fill: Color(0xFFFFDC45), deep: Color(0xFFE0B21C)),
    (name: 'Plum', fill: Color(0xFF9C4A8C), deep: Color(0xFF6E2C62)),
    (name: 'Orange', fill: Color(0xFFFF8F26), deep: Color(0xFFD9680A)),
    (name: 'Apple', fill: Color(0xFFE8413C), deep: Color(0xFFB02420)),
    (name: 'Pineapple', fill: Color(0xFFFFD23F), deep: Color(0xFFD99E14)),
    (name: 'Melon', fill: Color(0xFFBBD943), deep: Color(0xFF8AAE1F)),
    (name: 'Watermelon', fill: Color(0xFF3FAE4F), deep: Color(0xFF237A33)),
  ];

  final Map<int, Picture> _pictures = <int, Picture>{};

  /// Draws fruit [tier] centred at [at] with radius [radius].
  void draw(Canvas canvas, int tier, Offset at, double radius,
      {double rotation = 0, double squash = 0}) {
    final picture = _pictures.putIfAbsent(tier, () => _record(tier));
    canvas.save();
    canvas.translate(at.dx, at.dy);
    if (rotation != 0) canvas.rotate(rotation);
    final s = radius / 100;
    canvas.scale(s * (1 + squash * 0.12), s * (1 - squash * 0.12));
    canvas.drawPicture(picture);
    canvas.restore();
  }

  Picture _record(int tier) {
    final recorder = PictureRecorder();
    final c = Canvas(recorder);
    final colours = palette[tier];
    const r = 100.0;

    // Body with a darker lower-right shade and an ink outline.
    c.drawCircle(Offset.zero, r, Paint()..color = colours.deep);
    c.drawCircle(const Offset(-6, -8), r - 8, Paint()..color = colours.fill);

    switch (tier) {
      case 1: // strawberry seeds
        final seed = Paint()..color = const Color(0xFFFFF3A0);
        for (final p in const <Offset>[
          Offset(-45, 10), Offset(0, 40), Offset(45, 10), Offset(-25, 60),
          Offset(30, 62), Offset(-60, -25), Offset(60, -25),
        ]) {
          c.drawOval(Rect.fromCenter(center: p, width: 9, height: 14), seed);
        }
      case 2: // raspberry drupelets
        final bump = Paint()..color = colours.deep.withValues(alpha: 0.5);
        for (var ring = 0; ring < 2; ring++) {
          final rr = ring == 0 ? 72.0 : 40.0;
          final n = ring == 0 ? 12 : 7;
          for (var i = 0; i < n; i++) {
            final a = i * math.pi * 2 / n + ring * 0.3;
            c.drawCircle(Offset(math.cos(a) * rr, math.sin(a) * rr), 15, bump);
          }
        }
      case 5: // plum bloom
        c.drawOval(const Rect.fromLTWH(-60, -70, 50, 26),
            Paint()..color = const Color(0x33FFFFFF));
      case 6: // orange dimples
        final dot = Paint()..color = colours.deep.withValues(alpha: 0.4);
        for (final p in const <Offset>[Offset(-50, 40), Offset(-30, 60), Offset(55, 35), Offset(40, 60)]) {
          c.drawCircle(p, 5, dot);
        }
      case 8: // pineapple diamonds
        final hatch = Paint()
          ..color = colours.deep.withValues(alpha: 0.55)
          ..strokeWidth = 5
          ..style = PaintingStyle.stroke;
        c.save();
        c.clipPath(Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: r - 6)));
        for (var k = -150.0; k <= 150; k += 42) {
          c.drawLine(Offset(k - 120, -120), Offset(k + 120, 120), hatch);
          c.drawLine(Offset(k + 120, -120), Offset(k - 120, 120), hatch);
        }
        c.restore();
      case 9: // melon net
        final net = Paint()
          ..color = const Color(0xFFE8F5B0)
          ..strokeWidth = 5
          ..style = PaintingStyle.stroke;
        c.save();
        c.clipPath(Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: r - 6)));
        final rng = math.Random(4);
        for (var i = 0; i < 16; i++) {
          final a = Offset(rng.nextDouble() * 200 - 100, rng.nextDouble() * 200 - 100);
          final b = a + Offset(rng.nextDouble() * 80 - 40, rng.nextDouble() * 80 - 40);
          c.drawLine(a, b, net);
        }
        c.restore();
      case 10: // watermelon stripes
        final stripe = Paint()
          ..color = colours.deep
          ..strokeWidth = 14
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
        c.save();
        c.clipPath(Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: r - 4)));
        for (var k = -80.0; k <= 80; k += 40) {
          final path = Path()
            ..moveTo(k, -110)
            ..quadraticBezierTo(k + 22, 0, k, 110);
          c.drawPath(path, stripe);
        }
        c.restore();
    }

    // Shine.
    c.drawOval(const Rect.fromLTWH(-62, -70, 38, 24),
        Paint()..color = const Color(0x88FFFFFF));

    c.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..color = ElevarColors.ink.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7,
    );

    // Leaves, stems and crowns sit over the outline.
    final leaf = Paint()..color = const Color(0xFF3FAE4F);
    final leafLine = Paint()
      ..color = ElevarColors.ink.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;
    void leafAt(Offset at, double angle, double size) {
      c.save();
      c.translate(at.dx, at.dy);
      c.rotate(angle);
      final path = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(size * 0.5, -size * 0.45, size, 0)
        ..quadraticBezierTo(size * 0.5, size * 0.45, 0, 0);
      c.drawPath(path, leaf);
      c.drawPath(path, leafLine);
      c.restore();
    }

    switch (tier) {
      case 1 || 2:
        for (var i = -2; i <= 2; i++) {
          leafAt(const Offset(0, -92), -math.pi / 2 + i * 0.5, 40);
        }
      case 3 || 7:
        c.drawLine(const Offset(0, -95), const Offset(8, -128),
            Paint()
              ..color = const Color(0xFF6B4423)
              ..strokeWidth = 9
              ..strokeCap = StrokeCap.round);
        leafAt(const Offset(6, -110), -0.35, 48);
      case 8:
        for (var i = -3; i <= 3; i++) {
          leafAt(const Offset(0, -88), -math.pi / 2 + i * 0.28, 64 - i.abs() * 8);
        }
      case 9:
        c.drawLine(const Offset(0, -95), const Offset(18, -140),
            Paint()
              ..color = const Color(0xFF7A9A1A)
              ..strokeWidth = 11
              ..strokeCap = StrokeCap.round);
        c.drawLine(const Offset(0, -140), const Offset(36, -140),
            Paint()
              ..color = const Color(0xFF7A9A1A)
              ..strokeWidth = 11
              ..strokeCap = StrokeCap.round);
      default:
        break;
    }

    // Face.
    final ink = Paint()..color = const Color(0xFF2A1A12);
    c.drawCircle(const Offset(-30, 8), 9, ink);
    c.drawCircle(const Offset(30, 8), 9, ink);
    c.drawCircle(const Offset(-27, 5), 3, Paint()..color = const Color(0xFFFFFFFF));
    c.drawCircle(const Offset(33, 5), 3, Paint()..color = const Color(0xFFFFFFFF));
    final blush = Paint()..color = const Color(0x55FF6B8A);
    c.drawOval(Rect.fromCenter(center: const Offset(-50, 30), width: 26, height: 14), blush);
    c.drawOval(Rect.fromCenter(center: const Offset(50, 30), width: 26, height: 14), blush);
    c.drawArc(
      Rect.fromCenter(center: const Offset(0, 24), width: 30, height: 22),
      0.15,
      math.pi - 0.3,
      false,
      Paint()
        ..color = const Color(0xFF2A1A12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );

    return recorder.endRecording();
  }
}
