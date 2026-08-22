import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import '../state/session.dart';
import 'mode_select_screen.dart';

/// The hub. One playable game today, three seats reserved.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _PointsHeader(),
              const SizedBox(height: 34),
              Text('ELEVAR', style: ElevarType.display(52)),
              Text(
                'PLAY',
                style: ElevarType.display(52, color: ElevarColors.table),
              ),
              const SizedBox(height: 6),
              Text(
                'Pass the phone, or take on the machine.',
                style: ElevarType.body(15, color: ElevarColors.muted),
              ),
              const SizedBox(height: 30),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.88,
                  children: [
                    _GameTile(
                      title: 'PING\nPONG',
                      color: ElevarColors.table,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ModeSelectScreen(),
                        ),
                      ),
                    ),
                    const _GameTile(title: 'AIR\nHOCKEY', color: ElevarColors.p2),
                    const _GameTile(title: 'REACTION\nDUEL', color: ElevarColors.p1),
                    const _GameTile(title: 'TAP\nRACE', color: ElevarColors.ball),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PointsHeader extends StatelessWidget {
  const _PointsHeader();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: sessionPoints,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: ElevarColors.surfaceRaised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ElevarColors.ink, width: 3),
          ),
          child: Row(
            children: [
              const Icon(Icons.bolt_rounded, color: ElevarColors.ball, size: 26),
              const SizedBox(width: 8),
              Text(
                '${sessionPoints.pending}',
                style: ElevarType.display(28, color: ElevarColors.ball),
              ),
              const SizedBox(width: 6),
              Text('EP', style: ElevarType.label(12)),
              const Spacer(),
              // Honest about the state these points are actually in — and the
              // same badge offline play will show once syncing exists.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: ElevarColors.surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('PENDING SYNC', style: ElevarType.label(9)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GameTile extends StatelessWidget {
  const _GameTile({required this.title, required this.color, this.onTap});

  final String title;
  final Color color;
  final VoidCallback? onTap;

  bool get _available => onTap != null;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: _available ? color : ElevarColors.surfaceRaised,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: ElevarColors.ink, width: 4),
          boxShadow: _available
              ? const [
                  BoxShadow(color: ElevarColors.ink, offset: Offset(0, 6)),
                ]
              : null,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _available ? 'PLAY' : 'SOON',
              style: ElevarType.label(
                10,
                color: _available ? ElevarColors.ink : ElevarColors.muted,
              ),
            ),
            Text(
              title,
              style: ElevarType.display(
                26,
                color: _available ? ElevarColors.ink : ElevarColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
