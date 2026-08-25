import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import '../data/points_repository.dart';
import '../data/rewards_catalog.dart';
import '../games/elevar_game.dart';
import '../games/registry.dart';
import 'format.dart';

/// What EP is for, and what this device has earned so far.
class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  int _balance = 0;
  int _lifetimeMatches = 0;
  List<GameStat> _stats = const <GameStat>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final balance = await pointsRepository.balance();
    final stats = await pointsRepository.perGameStats();
    if (!mounted) return;
    setState(() {
      _balance = balance;
      _stats = stats;
      _lifetimeMatches = stats.fold<int>(0, (sum, stat) => sum + stat.played);
    });
  }

  String _titleFor(String slug) => elevarGames
      .firstWhere(
        (game) => game.slug == slug,
        orElse: () => const ComingSoonFallback(),
      )
      .title
      .replaceAll('\n', ' ');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
          children: <Widget>[
            Row(
              children: <Widget>[
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: ElevarColors.white,
                ),
                Text('REWARDS', style: ElevarType.display(24)),
              ],
            ),
            const SizedBox(height: 14),
            _BalanceCard(balance: _balance, matches: _lifetimeMatches),
            const SizedBox(height: 24),
            Text('SPEND IT ON', style: ElevarType.label(11)),
            const SizedBox(height: 12),
            for (final reward in RewardsCatalog.all) ...<Widget>[
              _RewardCard(reward: reward, balance: _balance),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 12),
            if (_stats.isNotEmpty) ...<Widget>[
              Text('YOUR RECORD', style: ElevarType.label(11)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: ElevarColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: ElevarColors.ink, width: 3),
                ),
                child: Column(
                  children: <Widget>[
                    for (final stat in _stats)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                _titleFor(stat.slug),
                                style: ElevarType.display(16),
                              ),
                            ),
                            Text(
                              '${stat.won}/${stat.played} won',
                              style: ElevarType.body(
                                13,
                                color: ElevarColors.muted,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '${stat.points} EP',
                              style: ElevarType.display(
                                16,
                                color: ElevarColors.ball,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            _HowItWorks(),
          ],
        ),
      ),
    );
  }
}

/// Fills in when a stat row names a game that is no longer in the registry —
/// a match played on a build that had a game this one does not.
class ComingSoonFallback extends ComingSoonGame {
  const ComingSoonFallback()
      : super(
            slug: 'unknown', title: 'RETIRED GAME', accent: ElevarColors.muted);
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance, required this.matches});

  final int balance;
  final int matches;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: ElevarColors.ball,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: ElevarColors.ink, width: 4),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: ElevarColors.ink, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('YOUR BALANCE',
              style: ElevarType.label(11, color: ElevarColors.ink)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              // A five-figure balance at 52pt ran 11 pixels past the card.
              // Scale it rather than clip it — the number is the point of the
              // card, so it should stay as large as it can be.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(groupedNumber(balance),
                      style: ElevarType.display(52, color: ElevarColors.ink)),
                ),
              ),
              const SizedBox(width: 8),
              Text('EP',
                  style: ElevarType.display(22, color: ElevarColors.ink)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            matches == 0
                ? 'Play a match to start earning.'
                : 'From $matches ${matches == 1 ? "match" : "matches"} played.',
            style: ElevarType.body(14, color: ElevarColors.ink)
                .copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _RewardCard extends StatelessWidget {
  const _RewardCard({required this.reward, required this.balance});

  final Reward reward;
  final int balance;

  @override
  Widget build(BuildContext context) {
    final affordable = balance >= reward.costPoints;
    final progress = (balance / reward.costPoints).clamp(0.0, 1.0).toDouble();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ElevarColors.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: affordable ? reward.accent : ElevarColors.ink,
          width: 3,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: reward.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: ElevarColors.ink, width: 2),
                ),
              ),
              const SizedBox(width: 8),
              // Expanded rather than a Spacer after it: the brand name is the
              // one part of this row that can grow, so it is the part that
              // should give way on a narrow phone.
              Expanded(
                child: Text(
                  reward.brand,
                  style: ElevarType.label(9),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${groupedNumber(reward.costPoints)} EP',
                style: ElevarType.display(
                  18,
                  color: affordable ? reward.accent : ElevarColors.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(reward.title, style: ElevarType.display(24)),
          const SizedBox(height: 3),
          Text(
            reward.detail,
            style: ElevarType.body(13, color: ElevarColors.muted),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: ElevarColors.surface,
              valueColor: AlwaysStoppedAnimation<Color>(reward.accent),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              // Expanded, not a Spacer: the progress line is the variable-width
              // half of this row, and letting it size to its natural width
              // overflowed a 390pt phone by 36 pixels.
              Expanded(
                child: Text(
                  affordable
                      ? 'Unlocked'
                      : '${reward.costPoints - balance} EP to go',
                  style: ElevarType.body(
                    12,
                    color: affordable ? reward.accent : ElevarColors.muted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              // Deliberately not a live button. Redemption needs an account to
              // attach a voucher to and a server that can hold, confirm and
              // settle it against the ledger — Phase 5. A button that did
              // nothing would be worse than no button.
              const Icon(Icons.lock_outline_rounded,
                  size: 13, color: ElevarColors.muted),
              const SizedBox(width: 4),
              Text('SOON', style: ElevarType.label(9)),
            ],
          ),
        ],
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ElevarColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ElevarColors.surfaceRaised, width: 3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('HOW YOU EARN', style: ElevarType.label(11)),
          const SizedBox(height: 10),
          _Rule('Finish a match', '+10 EP'),
          _Rule('Beat the bot', 'up to +33 EP'),
          _Rule('Play well', 'up to +15 EP'),
          _Rule('Daily streak', 'up to ×1.5'),
          const SizedBox(height: 10),
          Text(
            'Matches 6–10 each day pay half, and 11 onward a tenth. '
            'Everything stops at 300 EP a day. Nobody grinds their way to a '
            'free pair, which is what keeps the rewards worth having.',
            style: ElevarType.body(12, color: ElevarColors.muted),
          ),
        ],
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Expanded(child: Text(label, style: ElevarType.body(13))),
          const SizedBox(width: 12),
          Text(value, style: ElevarType.display(15, color: ElevarColors.ball)),
        ],
      ),
    );
  }
}
