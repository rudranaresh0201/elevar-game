import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import '../data/points_repository.dart';
import '../games/elevar_game.dart';
import '../games/registry.dart';
import 'format.dart';
import 'rewards_screen.dart';

/// The hub.
///
/// Every tile comes from [elevarGames]; there is no per-game branch anywhere in
/// this file. That is the payoff from building the plugin contract — the hub
/// stopped needing to know what games exist the moment there were two of them.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _balance = 0;
  int _streak = 0;
  int _pending = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final balance = await pointsRepository.balance();
    final today = await pointsRepository.todaySoFar();
    final pending = await pointsRepository.pendingSyncCount();
    if (!mounted) return;
    setState(() {
      _balance = balance;
      _streak = today.streakDays;
      _pending = pending;
    });
  }

  Future<void> _open(ElevarGame game) async {
    if (!game.isPlayable) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: game.buildModeSelect),
    );
    // Points may have been earned while we were away.
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: ElevarColors.table,
          backgroundColor: ElevarColors.surfaceRaised,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            children: <Widget>[
              _PointsHeader(
                balance: _balance,
                streak: _streak,
                pending: _pending,
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const RewardsScreen(),
                    ),
                  );
                  await _refresh();
                },
              ),
              const SizedBox(height: 28),
              Text('ELEVAR', style: ElevarType.display(54)),
              Text(
                'PLAY',
                style: ElevarType.display(54, color: ElevarColors.table),
              ),
              const SizedBox(height: 8),
              Text(
                'One phone. Two thumbs each. Points that spend.',
                style: ElevarType.body(15, color: ElevarColors.muted),
              ),
              const SizedBox(height: 24),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 0.9,
                children: <Widget>[
                  for (final game in elevarGames)
                    _GameTile(game: game, onTap: () => _open(game)),
                ],
              ),
              const SizedBox(height: 20),
              _RewardsCta(
                balance: _balance,
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const RewardsScreen(),
                    ),
                  );
                  await _refresh();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PointsHeader extends StatelessWidget {
  const _PointsHeader({
    required this.balance,
    required this.streak,
    required this.pending,
    required this.onTap,
  });

  final int balance;
  final int streak;
  final int pending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: ElevarColors.surfaceRaised,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ElevarColors.ink, width: 3),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.bolt_rounded, color: ElevarColors.ball, size: 28),
            const SizedBox(width: 6),
            // Expanded, not a Spacer after a naturally-sized number. A player
            // with five figures of EP and both chips showing overflowed a
            // 390pt phone by 113 pixels — and five figures is what a few weeks
            // of daily play actually looks like.
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      groupedNumber(balance),
                      style: ElevarType.display(30, color: ElevarColors.ball),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('EP', style: ElevarType.label(11)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (streak > 1) ...<Widget>[
              _Chip(
                icon: Icons.local_fire_department_rounded,
                label: '$streak',
                color: ElevarColors.p1,
              ),
              const SizedBox(width: 6),
            ],
            // Honest about where the points actually are. This badge is not a
            // placeholder for a backend — offline play will show exactly this
            // state once the server exists, because a match is banked locally
            // first and confirmed later either way.
            if (pending > 0)
              _Chip(
                icon: Icons.cloud_upload_outlined,
                label: '$pending',
                color: ElevarColors.muted,
              ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: ElevarColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 4),
          Text(label, style: ElevarType.display(14, color: color)),
        ],
      ),
    );
  }
}

class _GameTile extends StatelessWidget {
  const _GameTile({required this.game, required this.onTap});

  final ElevarGame game;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final available = game.isPlayable;
    return GestureDetector(
      onTap: available ? onTap : null,
      child: Container(
        decoration: BoxDecoration(
          color: available ? game.accent : ElevarColors.surfaceRaised,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: ElevarColors.ink, width: 4),
          boxShadow: available
              ? const <BoxShadow>[
                  BoxShadow(color: ElevarColors.ink, offset: Offset(0, 6)),
                ]
              : null,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: available
                    ? ElevarColors.ink.withValues(alpha: 0.22)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                available ? 'PLAY' : 'SOON',
                style: ElevarType.label(
                  10,
                  color: available ? ElevarColors.ink : ElevarColors.muted,
                ),
              ),
            ),
            // Scaled rather than wrapped. At 26pt a title like "RACING" does
            // not fit a tile on a 320pt phone, and wrapping it to a third line
            // overflowed the tile by 42 pixels. Inside a FittedBox the text
            // lays out unbounded and is scaled down to fit instead.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.bottomLeft,
                child: Text(
                  game.title,
                  style: ElevarType.display(
                    26,
                    color: available ? ElevarColors.ink : ElevarColors.muted,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The reason the points exist.
class _RewardsCta extends StatelessWidget {
  const _RewardsCta({required this.balance, required this.onTap});

  final int balance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: ElevarColors.ball,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: ElevarColors.ink, width: 4),
          boxShadow: const <BoxShadow>[
            BoxShadow(color: ElevarColors.ink, offset: Offset(0, 6)),
          ],
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'SPEND YOUR EP',
                    style: ElevarType.display(24, color: ElevarColors.ink),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Turn points into money off a pair.',
                    style: ElevarType.body(
                      14,
                      color: ElevarColors.ink,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_rounded,
                color: ElevarColors.ink, size: 30),
          ],
        ),
      ),
    );
  }
}
