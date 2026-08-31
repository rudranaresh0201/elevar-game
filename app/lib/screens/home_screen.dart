import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import '../data/player_profile.dart';
import '../data/points_repository.dart';
import '../data/profile_repository.dart';
import '../games/elevar_game.dart';
import '../games/registry.dart';
import 'format.dart';

/// The hub.
///
/// Every tile comes from [elevarGames]; there is no per-game branch anywhere
/// in this file. That is the payoff from building the plugin contract — the
/// hub stopped needing to know what games exist the moment there were two of
/// them, and a fourth game arriving changed nothing here at all.
///
/// The page is ordered by what a returning player is actually looking for:
/// what their points are worth, what is new, then everything else. The
/// leaderboard and the shop are one tap away in the bar rather than a scroll
/// away at the bottom of this list.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.onSeeLeaderboard,
    required this.onSpendPoints,
    super.key,
  });

  final VoidCallback onSeeLeaderboard;
  final VoidCallback onSpendPoints;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _balance = 0;
  int _streak = 0;
  int _pending = 0;
  int _pointsToday = 0;
  PlayerProfile? _profile;

  /// The soft daily ceiling from `scoring/points_estimate.dart`.
  ///
  /// Duplicated here to draw a progress bar, and that duplication is why it is
  /// called *soft*: the number that actually binds lives on the server, and
  /// this one going stale costs a slightly wrong bar rather than a wrong
  /// payout.
  static const int _dailyCap = 300;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final balance = await pointsRepository.balance();
    final today = await pointsRepository.todaySoFar();
    final pending = await pointsRepository.pendingSyncCount();
    final profile = await profileRepository.profile();
    if (!mounted) return;
    setState(() {
      _balance = balance;
      _streak = today.streakDays;
      _pointsToday = today.points;
      _pending = pending;
      _profile = profile;
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
    final playable =
        elevarGames.where((game) => game.isPlayable).toList(growable: false);
    // The newest playable game gets the wide tile. Taken from the front of the
    // registry rather than named here, so shipping game five is still one line
    // in one file.
    final featured = playable.isEmpty ? null : playable.first;
    final rest = <ElevarGame>[
      ...playable.skip(1),
      ...elevarGames.where((game) => !game.isPlayable),
    ];

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _refresh,
        color: ElevarColors.table,
        backgroundColor: ElevarColors.surfaceRaised,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: <Widget>[
            _Greeting(profile: _profile, streak: _streak),
            const SizedBox(height: 16),
            _BalanceCard(
              balance: _balance,
              pointsToday: _pointsToday,
              dailyCap: _dailyCap,
              pending: _pending,
              onSpend: widget.onSpendPoints,
              onRank: widget.onSeeLeaderboard,
            ),
            const SizedBox(height: 26),
            if (featured != null) ...<Widget>[
              _SectionHeading(
                title: 'NEWEST',
                trailing: 'JUST LANDED',
                trailingColour: featured.accent,
              ),
              const SizedBox(height: 10),
              _FeaturedTile(game: featured, onTap: () => _open(featured)),
              const SizedBox(height: 26),
            ],
            const _SectionHeading(title: 'ALL GAMES'),
            const SizedBox(height: 10),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.98,
              children: <Widget>[
                for (final game in rest)
                  _GameTile(game: game, onTap: () => _open(game)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.profile, required this.streak});

  final PlayerProfile? profile;
  final int streak;

  @override
  Widget build(BuildContext context) {
    final avatar = profile == null
        ? PlayerAvatars.all.first
        : PlayerAvatars.at(profile!.avatarIndex);

    return Row(
      children: <Widget>[
        Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: avatar.colour,
            shape: BoxShape.circle,
            border: Border.all(color: ElevarColors.ink, width: 3),
          ),
          child: Text(avatar.emoji, style: const TextStyle(fontSize: 20)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('ELEVAR', style: ElevarType.label(9)),
              const SizedBox(height: 2),
              Text(
                profile?.displayName ?? 'PLAY',
                style: ElevarType.display(22),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (streak > 1)
          _Chip(
            icon: Icons.local_fire_department_rounded,
            label: '$streak',
            colour: ElevarColors.p1,
          ),
      ],
    );
  }
}

/// What the points are, what they are worth, and how much more today can pay.
///
/// The daily progress bar is the one piece of the economy a player has to be
/// able to see. Diminishing returns and a cap are what bound the voucher
/// liability, and a player who does not know they have hit the cap concludes
/// the game stopped paying and stops playing — which costs more than the cap
/// ever saved.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.balance,
    required this.pointsToday,
    required this.dailyCap,
    required this.pending,
    required this.onSpend,
    required this.onRank,
  });

  final int balance;
  final int pointsToday;
  final int dailyCap;
  final int pending;
  final VoidCallback onSpend;
  final VoidCallback onRank;

  @override
  Widget build(BuildContext context) {
    final fraction = (pointsToday / dailyCap).clamp(0.0, 1.0);
    final capped = pointsToday >= dailyCap;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ElevarColors.surfaceRaised,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: ElevarColors.ink, width: 4),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: ElevarColors.ink, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              // The bolt is the app's one recurring symbol for points, and it
              // is also how the layout tests reach the shop.
              GestureDetector(
                onTap: onSpend,
                child: const Icon(
                  Icons.bolt_rounded,
                  color: ElevarColors.ball,
                  size: 30,
                ),
              ),
              const SizedBox(width: 6),
              // Expanded rather than a Spacer after a naturally-sized number.
              // A player with five figures of EP and both chips showing
              // overflowed a 390pt phone by 113 pixels — and five figures is
              // what a few weeks of daily play actually looks like.
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        groupedNumber(balance),
                        style: ElevarType.display(34, color: ElevarColors.ball),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('EP', style: ElevarType.label(11)),
                  ],
                ),
              ),
              if (pending > 0) ...<Widget>[
                const SizedBox(width: 6),
                // Honest about where the points actually are. Not a
                // placeholder for a backend — offline play will show exactly
                // this once the server exists, because a match is banked
                // locally first and confirmed later either way.
                _Chip(
                  icon: Icons.cloud_upload_outlined,
                  label: '$pending',
                  colour: ElevarColors.muted,
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Flexible(
                child: Text(
                  capped ? 'DAILY CAP REACHED' : 'EARNED TODAY',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ElevarType.label(
                    9,
                    color: capped ? ElevarColors.ball : ElevarColors.muted,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$pointsToday / $dailyCap',
                style: ElevarType.display(13, color: ElevarColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 10,
              backgroundColor: ElevarColors.surface,
              valueColor: AlwaysStoppedAnimation<Color>(
                capped ? ElevarColors.p1 : ElevarColors.table,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: ChunkyButton(
                  label: 'SPEND EP',
                  fontSize: 15,
                  color: ElevarColors.ball,
                  onPressed: onSpend,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ChunkyButton(
                  label: 'RANKINGS',
                  fontSize: 15,
                  color: ElevarColors.table,
                  onPressed: onRank,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
    this.trailing,
    this.trailingColour,
  });

  final String title;
  final String? trailing;
  final Color? trailingColour;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text(title, style: ElevarType.label(10)),
        const Spacer(),
        if (trailing != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: trailingColour ?? ElevarColors.table,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: ElevarColors.ink, width: 2),
            ),
            child: Text(
              trailing!,
              style: ElevarType.label(9, color: ElevarColors.ink),
            ),
          ),
      ],
    );
  }
}

/// The wide tile at the top.
///
/// Worth the vertical space it costs: a grid of equal squares says every game
/// is the same, and the one thing a returning player most wants to know is
/// what is different since last time.
class _FeaturedTile extends StatelessWidget {
  const _FeaturedTile({required this.game, required this.onTap});

  final ElevarGame game;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 142,
        decoration: BoxDecoration(
          color: game.accent,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: ElevarColors.ink, width: 4),
          boxShadow: const <BoxShadow>[
            BoxShadow(color: ElevarColors.ink, offset: Offset(0, 6)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            children: <Widget>[
              // The glyph, oversized and half off the edge. Cheaper than art,
              // and it scales to any tile size without a raster asset.
              Positioned(
                right: -18,
                bottom: -26,
                child: Icon(
                  game.glyph,
                  size: 150,
                  color: ElevarColors.ink.withValues(alpha: 0.16),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          game.title.replaceAll('\n', ' '),
                          style:
                              ElevarType.display(32, color: ElevarColors.ink),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            game.tagline,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: ElevarType.body(13, color: ElevarColors.ink)
                                .copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: ElevarColors.ink,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: ElevarColors.white,
                            size: 22,
                          ),
                        ),
                      ],
                    ),
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
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: <Widget>[
              Positioned(
                right: -14,
                bottom: -18,
                child: Icon(
                  game.glyph,
                  size: 96,
                  color: available
                      ? ElevarColors.ink.withValues(alpha: 0.16)
                      : ElevarColors.muted.withValues(alpha: 0.16),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
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
                          color:
                              available ? ElevarColors.ink : ElevarColors.muted,
                        ),
                      ),
                    ),
                    // Scaled rather than wrapped. At 26pt a title like
                    // "RACING" does not fit a tile on a 320pt phone, and
                    // wrapping it to a third line overflowed the tile by 42
                    // pixels. Inside a FittedBox the text lays out unbounded
                    // and is scaled down to fit instead.
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.bottomLeft,
                        child: Text(
                          game.title,
                          style: ElevarType.display(
                            24,
                            color: available
                                ? ElevarColors.ink
                                : ElevarColors.muted,
                          ),
                        ),
                      ),
                    ),
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

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.colour,
  });

  final IconData icon;
  final String label;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: ElevarColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colour, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: colour, size: 15),
          const SizedBox(width: 4),
          Text(label, style: ElevarType.display(14, color: colour)),
        ],
      ),
    );
  }
}
