import 'package:flutter/material.dart';

import 'colors.dart';
import 'theme.dart';

/// A player's score, as it appears on the table.
///
/// [upsideDown] flips the whole pill for the player sitting at the far end of
/// the phone. Two people sharing one screen face each other, so one of them
/// reads everything rotated — the reference artwork gets this right and it is
/// the single detail that makes a shared-screen game feel considered.
class ScorePill extends StatelessWidget {
  const ScorePill({
    required this.score,
    required this.color,
    this.upsideDown = false,
    this.label,
    super.key,
  });

  final int score;
  final Color color;
  final bool upsideDown;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(label!, style: ElevarType.label(11, color: ElevarColors.white)),
          const SizedBox(height: 2),
        ],
        Text(
          '$score',
          style: ElevarType.display(56, color: ElevarColors.white).copyWith(
            shadows: const [
              Shadow(color: ElevarColors.ink, offset: Offset(3, 3)),
            ],
          ),
        ),
      ],
    );

    return RotatedBox(
      quarterTurns: upsideDown ? 2 : 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ElevarColors.ink, width: 4),
        ),
        child: content,
      ),
    );
  }
}
