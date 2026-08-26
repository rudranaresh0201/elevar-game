import 'dart:math' as math;

import 'package:cricket_sim/cricket_sim.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';

import 'cricket_scene.dart';

/// The batting pad: one gesture carrying all three axes of a shot.
///
/// Drag to aim and release to play. The direction of the drag is where the ball
/// goes, its length is how hard, and **the moment of release is the timing** —
/// which is the whole skill of batting.
///
/// Folding three inputs into one gesture is what makes this feel like ping
/// pong's paddle rather than a control panel. The alternative — a direction
/// stick, a power slider and a swing button — is three targets for one thumb
/// and turns every ball into an admin task.
///
/// A plain tap is a zero-length drag, which falls out as a straight push at
/// medium power. That is the correct beginner shot and nobody has to be told.
class BattingPad extends StatefulWidget {
  const BattingPad({
    required this.onSwing,
    required this.enabled,
    super.key,
  });

  /// Fired once, on release.
  final void Function(CricketInput input) onSwing;

  /// False between balls, so a jab at the screen does not spend the next
  /// delivery's shot before the bowler has run in.
  final bool enabled;

  @override
  State<BattingPad> createState() => _BattingPadState();
}

class _BattingPadState extends State<BattingPad> {
  Offset? _from;
  Offset? _to;

  /// Drag distance that counts as full power. Deliberately short — a phone is
  /// not very tall and a shot that needs half the screen to play is a shot
  /// nobody plays twice.
  static const double _fullPower = 110;

  void _start(Offset at) {
    if (!widget.enabled) return;
    setState(() {
      _from = at;
      _to = at;
    });
  }

  void _move(Offset at) {
    if (_from == null) return;
    setState(() => _to = at);
  }

  void _end() {
    final from = _from;
    final to = _to;
    setState(() {
      _from = null;
      _to = null;
    });
    if (from == null || to == null || !widget.enabled) return;

    final delta = to - from;
    final distance = delta.distance;

    // Screen y and field y both increase downwards, so a swipe up the screen
    // is a shot back down the ground with no flipping needed.
    final direction = distance < 6
        ? const Offset(0, -1)
        : delta / distance;

    widget.onSwing(
      CricketInput(
        action: true,
        x: (direction.dx + 1) / 2,
        y: (direction.dy + 1) / 2,
        power: distance < 6
            ? 0.45
            : math.min(distance / _fullPower, 1).toDouble(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => _start(e.localPosition),
      onPointerMove: (e) => _move(e.localPosition),
      onPointerUp: (_) => _end(),
      onPointerCancel: (_) => _end(),
      child: CustomPaint(
        painter: _ShotPainter(from: _from, to: _to, enabled: widget.enabled),
        child: Center(
          child: _from != null
              ? null
              : Text(
                  widget.enabled ? 'SWIPE TO PLAY' : 'WAIT FOR THE BALL',
                  style: ElevarType.label(
                    12,
                    color: widget.enabled
                        ? ElevarColors.white
                        : ElevarColors.muted,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Draws the aim arrow and the power it carries, live under the thumb.
class _ShotPainter extends CustomPainter {
  const _ShotPainter({
    required this.from,
    required this.to,
    required this.enabled,
  });

  final Offset? from;
  final Offset? to;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final from = this.from;
    final to = this.to;
    if (from == null || to == null) return;

    final delta = to - from;
    final distance = delta.distance;
    final power = math.min(distance / 110, 1).toDouble();

    final colour = Color.lerp(
      ElevarColors.table,
      ElevarColors.p1,
      power,
    )!;

    canvas
      ..drawCircle(
        from,
        30,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = ElevarColors.white.withValues(alpha: 0.35),
      )
      // The shot itself: thicker and redder the harder it is being hit.
      ..drawLine(
        from,
        to,
        Paint()
          ..color = colour
          ..strokeWidth = 6 + 10 * power
          ..strokeCap = StrokeCap.round,
      )
      ..drawCircle(to, 12 + 10 * power, Paint()..color = colour);
  }

  @override
  bool shouldRepaint(_ShotPainter old) =>
      old.from != from || old.to != to || old.enabled != enabled;
}

/// The bowling pad: a plan view of the pitch you drop the ball onto.
///
/// Touch where you want it to land and release to bowl. Line is across, length
/// is down, and the four delivery chips change what the ball does after it
/// pitches. It is the same one-gesture idea as batting, and it means the half
/// of the match the player *bowls* is something they do rather than watch.
class BowlingPad extends StatefulWidget {
  const BowlingPad({
    required this.onBowl,
    required this.enabled,
    super.key,
  });

  final void Function(CricketInput input) onBowl;
  final bool enabled;

  @override
  State<BowlingPad> createState() => _BowlingPadState();
}

class _BowlingPadState extends State<BowlingPad> {
  Offset? _aim;
  Size _size = Size.zero;
  DeliveryKind _kind = DeliveryKind.pace;

  static double _powerFor(DeliveryKind kind) => switch (kind) {
        DeliveryKind.pace => 0.12,
        DeliveryKind.spin => 0.37,
        DeliveryKind.yorker => 0.62,
        DeliveryKind.bouncer => 0.87,
      };

  void _release() {
    final aim = _aim;
    setState(() => _aim = null);
    if (aim == null || !widget.enabled || _size.isEmpty) return;

    widget.onBowl(
      CricketInput(
        action: true,
        x: (aim.dx / _size.width).clamp(0.0, 1.0),
        y: (aim.dy / _size.height).clamp(0.0, 1.0),
        power: _powerFor(_kind),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _size = Size(constraints.maxWidth, constraints.maxHeight);
              return Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) => widget.enabled
                    ? setState(() => _aim = e.localPosition)
                    : null,
                onPointerMove: (e) => _aim == null
                    ? null
                    : setState(() => _aim = e.localPosition),
                onPointerUp: (_) => _release(),
                onPointerCancel: (_) => _release(),
                child: CustomPaint(
                  painter: _PitchPainter(aim: _aim, enabled: widget.enabled),
                  child: _aim == null
                      ? Center(
                          child: Text(
                            widget.enabled
                                ? 'TAP A LENGTH TO BOWL'
                                : 'BOWLING…',
                            style: ElevarType.label(
                              12,
                              color: widget.enabled
                                  ? ElevarColors.white
                                  : ElevarColors.muted,
                            ),
                          ),
                        )
                      : null,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            for (final kind in DeliveryKind.values)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: _KindChip(
                    kind: kind,
                    selected: _kind == kind,
                    onTap: () => setState(() => _kind = kind),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({
    required this.kind,
    required this.selected,
    required this.onTap,
  });

  final DeliveryKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? CricketColors.bowlerShirt
              : ElevarColors.surfaceRaised,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: ElevarColors.ink, width: 3),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              kind.name.toUpperCase(),
              style: ElevarType.display(
                12,
                color: selected ? ElevarColors.white : ElevarColors.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The pitch as seen from above, with the good length marked.
class _PitchPainter extends CustomPainter {
  const _PitchPainter({required this.aim, required this.enabled});

  final Offset? aim;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final pitch = Rect.fromLTWH(0, 0, size.width, size.height);

    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(pitch, const Radius.circular(12)),
        Paint()..color = CricketColors.pitch.withValues(alpha: 0.85),
      )
      ..drawRRect(
        RRect.fromRectAndRadius(pitch, const Radius.circular(12)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = ElevarColors.ink,
      );

    // The good-length band, which is the one piece of coaching the screen
    // gives: land it here and the batter is in trouble.
    final goodTop = size.height * 0.44;
    final goodHeight = size.height * 0.26;
    canvas.drawRect(
      Rect.fromLTWH(0, goodTop, size.width, goodHeight),
      Paint()..color = CricketColors.perfect.withValues(alpha: 0.22),
    );

    // Stumps at the batter's end, at the bottom.
    final stumpPaint = Paint()
      ..color = CricketColors.stumps
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    for (var i = -1; i <= 1; i++) {
      final x = size.width / 2 + i * 9;
      canvas.drawLine(
        Offset(x, size.height - 20),
        Offset(x, size.height - 4),
        stumpPaint,
      );
    }

    final aim = this.aim;
    if (aim == null) return;
    canvas
      ..drawCircle(
        aim,
        20,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = ElevarColors.white,
      )
      ..drawCircle(aim, 8, Paint()..color = CricketColors.ball);
  }

  @override
  bool shouldRepaint(_PitchPainter old) =>
      old.aim != aim || old.enabled != enabled;
}
