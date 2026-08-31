import 'package:cricket_sim/cricket_sim.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';

import 'cricket_scene.dart';

/// The crease, as a surface a thumb lives on.
///
/// This replaced a swipe pad with three shot buttons under it, and the change
/// is the whole point of the rebuild: **the bat is not a shot you choose, it is
/// a thing you hold somewhere.** Across the pad is across the crease; up and
/// down the pad raises and lowers the blade. Nothing here decides a direction,
/// a power or a shot type — the simulation reads the bat's own position and
/// velocity at the instant the ball reaches it, and every one of those falls
/// out for free.
///
/// Three consequences worth knowing, all of them the reason it is better:
///
/// * **Power is not a control.** How hard the ball goes is how fast the blade
///   was moving, so a player who flicks their thumb through the line hits it
///   further than one who parks it there. Nobody has to be taught that.
/// * **There is no timing window to be inside or outside of.** You are either
///   in the ball's way or you are not, which is also what being bowled *is*.
/// * **You can change your mind late, and it costs you.** The blade has a
///   speed cap, so a correction made after the ball pitches is a correction
///   that may not arrive.
class BatPad extends StatefulWidget {
  const BatPad({
    required this.onMove,
    required this.enabled,
    this.ballLine,
    super.key,
  });

  /// Fired continuously while a thumb is down, and once on release.
  final void Function(CricketInput input) onMove;

  /// False between balls. The bat still exists — it drifts back to its stance
  /// — but nothing the thumb does is worth sending.
  final bool enabled;

  /// Where the ball is heading across the crease, normalised, or null.
  ///
  /// The batting assist, and deliberately a *pre-bounce* projection: it shows
  /// the line the ball is on, not the line it will end up on after it deviates
  /// off the seam. An assist that gave away the movement would remove the only
  /// thing a bowler has.
  final double? ballLine;

  @override
  State<BatPad> createState() => _BatPadState();
}

class _BatPadState extends State<BatPad> {
  /// Where the thumb is, in the pad's own 0..1 space.
  Offset _at = Offset(
    CricketField.batStance.x,
    CricketField.batStance.y,
  );

  bool _down = false;

  void _send(Offset local, Size size) {
    final normalised = Offset(
      (local.dx / size.width).clamp(0.0, 1.0),
      (local.dy / size.height).clamp(0.0, 1.0),
    );
    setState(() => _at = normalised);
    if (!widget.enabled) return;
    // `action` and `power` are the bowler's channels; batting spends only two.
    widget.onMove(CricketInput(x: normalised.dx, y: normalised.dy));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            setState(() => _down = true);
            _send(e.localPosition, size);
          },
          onPointerMove: (e) => _send(e.localPosition, size),
          onPointerUp: (_) => setState(() => _down = false),
          onPointerCancel: (_) => setState(() => _down = false),
          child: CustomPaint(
            painter: _CreasePainter(
              at: _at,
              holding: _down,
              enabled: widget.enabled,
              ballLine: widget.ballLine,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  widget.enabled
                      ? (_down ? 'SWING THROUGH IT' : 'DRAG THE BAT')
                      : 'WAIT FOR THE BALL',
                  style: ElevarType.label(
                    11,
                    color: widget.enabled
                        ? ElevarColors.white
                        : ElevarColors.muted,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Draws the crease the thumb is moving the bat around.
class _CreasePainter extends CustomPainter {
  const _CreasePainter({
    required this.at,
    required this.holding,
    required this.enabled,
    required this.ballLine,
  });

  final Offset at;
  final bool holding;
  final bool enabled;
  final double? ballLine;

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()
      ..color = ElevarColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // The ground, at the bottom of the pad, because down the pad is down
    // toward the turf.
    canvas.drawLine(
      Offset(0, size.height - 6),
      Offset(size.width, size.height - 6),
      Paint()
        ..color = CricketColors.pitch
        ..strokeWidth = 6,
    );

    // Stump line, so "straight" is a visible place rather than a guess.
    final middle = size.width / 2;
    canvas.drawLine(
      Offset(middle, 18),
      Offset(middle, size.height - 6),
      Paint()
        ..color = ElevarColors.muted.withValues(alpha: 0.35)
        ..strokeWidth = 2,
    );

    // Where the ball is coming.
    final line = ballLine;
    if (line != null && enabled) {
      final x = line * size.width;
      canvas.drawLine(
        Offset(x, 16),
        Offset(x, size.height - 6),
        Paint()
          ..color = CricketColors.ball.withValues(alpha: 0.75)
          ..strokeWidth = 3,
      );
      canvas.drawCircle(
        Offset(x, size.height - 10),
        7,
        Paint()..color = CricketColors.ball,
      );
    }

    // The blade. Drawn where the thumb is rather than where the simulation has
    // got the bat to, on purpose: this is the control, and a control that lags
    // its own input feels broken even when the thing it drives is correct. The
    // real bat, speed-capped and possibly behind, is the one in the scene.
    final centre = Offset(at.dx * size.width, at.dy * size.height);
    final blade = Rect.fromCenter(
      center: centre,
      width: size.width * 0.13,
      height: size.height * 0.34,
    );
    final body = RRect.fromRectAndRadius(blade, const Radius.circular(6));

    canvas.drawRRect(
      body,
      Paint()
        ..color = enabled
            ? (holding ? CricketColors.bat : CricketColors.bat.withValues(alpha: 0.75))
            : ElevarColors.muted.withValues(alpha: 0.4),
    );
    canvas.drawRRect(body, ink..strokeWidth = 3);

    // Handle, so which end is which is obvious at a glance.
    canvas.drawLine(
      Offset(centre.dx, blade.top),
      Offset(centre.dx, blade.top - size.height * 0.12),
      Paint()
        ..color = ElevarColors.ink
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_CreasePainter old) =>
      old.at != at ||
      old.holding != holding ||
      old.enabled != enabled ||
      old.ballLine != ballLine;
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
