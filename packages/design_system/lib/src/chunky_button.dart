import 'package:flutter/material.dart';

import 'colors.dart';
import 'theme.dart';

/// The one button style in the app.
///
/// Thick black outline and a hard offset shadow rather than a soft blur — the
/// reference artwork has no gradients or gaussian anywhere, and mixing a
/// modern Material shadow into it reads immediately as a different app. Pressing
/// sinks the button onto its shadow, which is the whole animation budget and
/// enough.
class ChunkyButton extends StatefulWidget {
  const ChunkyButton({
    required this.label,
    required this.onPressed,
    this.color = ElevarColors.table,
    this.textColor = ElevarColors.ink,
    this.icon,
    this.fontSize = 26,
    this.expand = true,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final Color textColor;
  final IconData? icon;
  final double fontSize;
  final bool expand;

  @override
  State<ChunkyButton> createState() => _ChunkyButtonState();
}

class _ChunkyButtonState extends State<ChunkyButton> {
  bool _down = false;

  static const double _depth = 6;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final sunk = _down && enabled;

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 70),
          transform: Matrix4.translationValues(0, sunk ? _depth : 0, 0),
          width: widget.expand ? double.infinity : null,
          decoration: BoxDecoration(
            color: enabled ? widget.color : ElevarColors.muted,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: ElevarColors.ink, width: 4),
            boxShadow: sunk
                ? const []
                : const [
                    BoxShadow(
                      color: ElevarColors.ink,
                      offset: Offset(0, _depth),
                      blurRadius: 0,
                    ),
                  ],
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 26),
          child: Row(
            mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon,
                    color: widget.textColor, size: widget.fontSize),
                const SizedBox(width: 10),
              ],
              // Scaled, not clipped. A long label in a narrow button pushed
              // 65 pixels past its own edge on a 320pt phone; shrinking the
              // text keeps the button the size the layout asked for.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    style: ElevarType.display(
                      widget.fontSize,
                      color: widget.textColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A row of mutually exclusive chunky options — difficulty, match length.
class ChunkySegmented<T> extends StatelessWidget {
  const ChunkySegmented({
    required this.options,
    required this.selected,
    required this.onChanged,
    this.color = ElevarColors.table,
    super.key,
  });

  final Map<T, String> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final entry in options.entries) ...[
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(entry.key),
              child: Container(
                decoration: BoxDecoration(
                  color: entry.key == selected
                      ? color
                      : ElevarColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: ElevarColors.ink, width: 3),
                ),
                padding: const EdgeInsets.symmetric(vertical: 13),
                alignment: Alignment.center,
                child: Text(
                  entry.value,
                  style: ElevarType.display(
                    17,
                    color: entry.key == selected
                        ? ElevarColors.ink
                        : ElevarColors.muted,
                  ),
                ),
              ),
            ),
          ),
          if (entry.key != options.keys.last) const SizedBox(width: 10),
        ],
      ],
    );
  }
}
