import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:racing_sim/racing_sim.dart';

/// A button that reports whether a thumb is currently on it.
///
/// Deliberately a [Listener] rather than a [GestureDetector]. Two people
/// sharing a phone put up to eight thumbs on the glass at once, and the gesture
/// arena exists to decide which *single* recogniser wins a pointer — exactly
/// the wrong behaviour here, where four simultaneous presses are four
/// independent facts. A raw pointer listener has no arena and no ambiguity.
///
/// Flutter routes every later event for a pointer back to the widget that
/// received its down, so a thumb that slides off the button still reports its
/// release here rather than sticking on.
class HoldButton extends StatefulWidget {
  const HoldButton({
    required this.onChanged,
    required this.child,
    required this.color,
    this.width = 84,
    this.height = 88,
    super.key,
  });

  final ValueChanged<bool> onChanged;
  final Widget child;
  final Color color;
  final double width;
  final double height;

  @override
  State<HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<HoldButton> {
  /// Pointer ids currently down on this button. A count rather than a flag,
  /// because a second finger landing on a button the first is already holding
  /// must not release it when *it* lifts.
  final Set<int> _pointers = <int>{};

  bool get _down => _pointers.isNotEmpty;

  void _add(PointerDownEvent event) {
    final wasDown = _down;
    setState(() => _pointers.add(event.pointer));
    if (!wasDown) widget.onChanged(true);
  }

  void _remove(int pointer) {
    if (!_pointers.contains(pointer)) return;
    setState(() => _pointers.remove(pointer));
    if (!_down) widget.onChanged(false);
  }

  @override
  Widget build(BuildContext context) {
    const depth = 6.0;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _add,
      onPointerUp: (e) => _remove(e.pointer),
      onPointerCancel: (e) => _remove(e.pointer),
      child: SizedBox(
        width: widget.width,
        height: widget.height + depth,
        child: Padding(
          padding: EdgeInsets.only(top: _down ? depth : 0),
          child: Container(
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: ElevarColors.ink, width: 4),
              boxShadow: _down
                  ? const <BoxShadow>[]
                  : const <BoxShadow>[
                      BoxShadow(color: ElevarColors.ink, offset: Offset(0, depth)),
                    ],
            ),
            alignment: Alignment.center,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// One driver's controls: a steering rocker on one side, the pedals on the
/// other.
///
/// Reports a whole [CarInput] on every change rather than individual button
/// events, so the game never has to reassemble the control state and can never
/// hold a stale half of it.
class DriverControls extends StatefulWidget {
  const DriverControls({
    required this.onInput,
    required this.color,
    this.autoGas = false,
    this.upsideDown = false,
    super.key,
  });

  final ValueChanged<CarInput> onInput;
  final Color color;

  /// Holds the throttle down automatically, leaving the player to steer and
  /// brake. On by default — see [RaceConfig.autoGas] for why.
  final bool autoGas;

  /// P2 sits at the far end of the phone and reads everything rotated, exactly
  /// as they do the ping pong score pill.
  final bool upsideDown;

  @override
  State<DriverControls> createState() => _DriverControlsState();
}

class _DriverControlsState extends State<DriverControls> {
  bool _left = false;
  bool _right = false;
  bool _gas = false;
  bool _brake = false;

  @override
  void initState() {
    super.initState();
    // Publish the resting state once, before anything is touched.
    //
    // Without this, auto-gas did nothing at all until the player pressed some
    // *other* button: the simulation holds the last input it was given, and
    // with no touch there was never a first one — so the throttle that is
    // supposed to be held for you was never actually held. A car that does not
    // move when the lights go out is exactly the bug this whole pass is about.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _emit();
    });
  }

  @override
  void didUpdateWidget(DriverControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoGas != widget.autoGas) _emit();
  }

  void _emit() {
    // Both directions at once cancel out, which is what a real rocker does and
    // what a player expects when they fumble.
    final steer = (_right ? 1 : 0) - (_left ? 1 : 0);
    widget.onInput(
      CarInput(
        steer: steer,
        throttle: widget.autoGas ? !_brake : _gas,
        brake: _brake,
      ),
    );
  }

  /// Relative widths of the four targets. The gas pedal is the one a thumb
  /// rests on for a whole race, so it gets the most glass; the brake is a stab
  /// and can be smaller.
  static const double _steerUnits = 1.0;
  static const double _brakeUnits = 0.85;
  static const double _gasUnits = 1.3;
  static const double _gap = 10;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Sized from the space actually available rather than from fixed
        // pixels. Fixed widths came to 402pt against the 358pt a 390pt phone
        // offers, which overflowed the row on the most common screen there is.
        const horizontalPadding = 14.0;
        final available = constraints.maxWidth - horizontalPadding * 2;

        // A flexible gap between the two clusters, so thumbs are not crowded
        // together in the middle of the phone.
        final middleGap = (available * 0.06).clamp(14.0, 44.0);
        const totalUnits = _steerUnits * 2 + _brakeUnits + _gasUnits;
        final unit =
            ((available - _gap * 2 - middleGap) / totalUnits).clamp(52.0, 104.0);

        // Leave room for the press-down travel and the padding above and below.
        final buttonHeight =
            (constraints.maxHeight - 22).clamp(56.0, 92.0).toDouble();

        final rocker = Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            HoldButton(
              width: unit * _steerUnits,
              height: buttonHeight,
              color: widget.color,
              onChanged: (v) {
                _left = v;
                _emit();
              },
              child: _Glyph('◀', unit),
            ),
            const SizedBox(width: _gap),
            HoldButton(
              width: unit * _steerUnits,
              height: buttonHeight,
              color: widget.color,
              onChanged: (v) {
                _right = v;
                _emit();
              },
              child: _Glyph('▶', unit),
            ),
          ],
        );

        final pedals = Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            HoldButton(
              width: unit * _brakeUnits,
              height: buttonHeight,
              color: ElevarColors.surfaceRaised,
              onChanged: (v) {
                _brake = v;
                _emit();
              },
              child: Text(
                'BRAKE',
                style: ElevarType.display(
                  (unit * 0.17).clamp(11.0, 16.0),
                  color: ElevarColors.white,
                ),
              ),
            ),
            const SizedBox(width: _gap),
            if (widget.autoGas)
              _AutoGasChip(
                color: widget.color,
                width: unit * _gasUnits,
                height: buttonHeight,
              )
            else
              HoldButton(
                width: unit * _gasUnits,
                height: buttonHeight,
                color: ElevarColors.ball,
                onChanged: (v) {
                  _gas = v;
                  _emit();
                },
                child: Text(
                  'GAS',
                  style: ElevarType.display(
                    (unit * 0.28).clamp(16.0, 26.0),
                    color: ElevarColors.ink,
                  ),
                ),
              ),
          ],
        );

        final content = Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: 6,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[rocker, pedals],
          ),
        );

        return RotatedBox(
          quarterTurns: widget.upsideDown ? 2 : 0,
          child: content,
        );
      },
    );
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph(this.glyph, this.unit);

  final String glyph;
  final double unit;

  @override
  Widget build(BuildContext context) => Text(
        glyph,
        style: ElevarType.display(
          (unit * 0.36).clamp(20.0, 34.0),
          color: ElevarColors.ink,
        ),
      );
}

class _AutoGasChip extends StatelessWidget {
  const _AutoGasChip({
    required this.color,
    required this.width,
    required this.height,
  });

  final Color color;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height + 6,
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: ElevarColors.ink, width: 4),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('AUTO',
                style: ElevarType.display(16, color: ElevarColors.white)),
            Text('GAS', style: ElevarType.label(9)),
          ],
        ),
      ),
    );
  }
}
