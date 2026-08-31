import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import '../data/leaderboard_client.dart';
import '../data/leaderboard_service.dart';
import '../data/player_profile.dart';
import '../data/points_repository.dart';
import '../data/profile_repository.dart';
import 'format.dart';

/// Where you are against everybody else.
///
/// The board is served by a webhook — see [LeaderboardConfig] — and the screen
/// is built around the fact that the webhook might not answer, or might not
/// exist yet. There is no spinner-forever state and no blank list: it always
/// shows the player their own lifetime total, and layers the world's numbers
/// on top when it has them.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({this.service, super.key});

  /// Injected by tests. In the app this is built from the compiled-in
  /// endpoint.
  final LeaderboardService? service;

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  late final LeaderboardService _service =
      widget.service ?? LeaderboardService();

  BoardResult? _board;
  PlayerProfile? _profile;
  int _lifetime = 0;
  int _matches = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);

    final profile = await profileRepository.profile();
    final lifetime = await pointsRepository.lifetimePoints();
    final stats = await pointsRepository.perGameStats();
    final board = await _service.refresh();

    if (!mounted) return;
    setState(() {
      _profile = profile;
      _lifetime = lifetime;
      _matches = stats.fold<int>(0, (sum, stat) => sum + stat.played);
      _board = board;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final board = _board;

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _load,
        color: ElevarColors.table,
        backgroundColor: ElevarColors.surfaceRaised,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          children: <Widget>[
            Text('LEADERBOARD', style: ElevarType.display(30)),
            const SizedBox(height: 4),
            Text(
              'Lifetime EP. Spending it never costs you your place.',
              style: ElevarType.body(14, color: ElevarColors.muted),
            ),
            const SizedBox(height: 18),
            _YouCard(
              profile: _profile,
              lifetime: _lifetime,
              matches: _matches,
              rank: board?.snapshot.yourRank,
            ),
            const SizedBox(height: 18),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: CircularProgressIndicator(
                    color: ElevarColors.table,
                  ),
                ),
              )
            else if (board != null) ...<Widget>[
              _StatusNote(board: board),
              const SizedBox(height: 12),
              if (board.snapshot.isEmpty)
                const _EmptyBoard()
              else
                for (final row in board.snapshot.rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _BoardRow(row: row),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The player's own card, which is always present.
///
/// It is the first thing on the screen rather than a row buried in a list,
/// because on a board of any size that row is off screen — and the number a
/// player came here to see is their own.
class _YouCard extends StatelessWidget {
  const _YouCard({
    required this.profile,
    required this.lifetime,
    required this.matches,
    required this.rank,
  });

  final PlayerProfile? profile;
  final int lifetime;
  final int matches;
  final int? rank;

  @override
  Widget build(BuildContext context) {
    final avatar = profile == null
        ? PlayerAvatars.all.first
        : PlayerAvatars.at(profile!.avatarIndex);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ElevarColors.surfaceRaised,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: ElevarColors.ball, width: 4),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: ElevarColors.ink, offset: Offset(0, 6)),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: avatar.colour,
              shape: BoxShape.circle,
              border: Border.all(color: ElevarColors.ink, width: 3),
            ),
            child: Text(avatar.emoji, style: const TextStyle(fontSize: 24)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('YOU', style: ElevarType.label(9)),
                const SizedBox(height: 2),
                Text(
                  profile?.displayName ?? '…',
                  style: ElevarType.display(20),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '$matches ${matches == 1 ? 'match' : 'matches'} played',
                  style: ElevarType.body(12, color: ElevarColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                groupedNumber(lifetime),
                style: ElevarType.display(26, color: ElevarColors.ball),
              ),
              Text('EP EARNED', style: ElevarType.label(8)),
              if (rank != null) ...<Widget>[
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: ElevarColors.table,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: ElevarColors.ink, width: 2),
                  ),
                  child: Text(
                    '#$rank',
                    style: ElevarType.display(14, color: ElevarColors.ink),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Says which of the three states the board is in.
class _StatusNote extends StatelessWidget {
  const _StatusNote({required this.board});

  final BoardResult board;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String text, Color colour) = switch (board.status) {
      BoardStatus.live => (
          Icons.public_rounded,
          'Live · updated just now',
          ElevarColors.table,
        ),
      BoardStatus.stale => (
          Icons.cloud_off_rounded,
          board.snapshot.fetchedAt == null
              ? (board.error ?? 'Could not reach the leaderboard.')
              : 'Showing the last board we had · '
                  '${_age(board.snapshot.fetchedAt!)}',
          ElevarColors.muted,
        ),
      BoardStatus.notConfigured => (
          Icons.construction_rounded,
          'Global rankings switch on when the season server goes live. '
              'Your EP is already being counted.',
          ElevarColors.muted,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: ElevarColors.surfaceRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colour, width: 2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: colour),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: ElevarType.body(13, color: ElevarColors.muted),
            ),
          ),
        ],
      ),
    );
  }

  static String _age(DateTime at) {
    final delta = DateTime.now().difference(at);
    if (delta.inMinutes < 1) return 'moments ago';
    if (delta.inHours < 1) return '${delta.inMinutes} min ago';
    if (delta.inDays < 1) return '${delta.inHours} h ago';
    return '${delta.inDays} d ago';
  }
}

class _EmptyBoard extends StatelessWidget {
  const _EmptyBoard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 18),
      decoration: BoxDecoration(
        color: ElevarColors.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ElevarColors.ink, width: 3),
      ),
      child: Column(
        children: <Widget>[
          const Icon(
            Icons.emoji_events_rounded,
            size: 42,
            color: ElevarColors.muted,
          ),
          const SizedBox(height: 12),
          Text(
            'NOBODY HERE YET',
            style: ElevarType.display(18, color: ElevarColors.muted),
          ),
          const SizedBox(height: 6),
          Text(
            'Keep playing. Every point you bank counts towards '
            'your place when the board opens.',
            textAlign: TextAlign.center,
            style: ElevarType.body(13, color: ElevarColors.muted),
          ),
        ],
      ),
    );
  }
}

class _BoardRow extends StatelessWidget {
  const _BoardRow({required this.row});

  final LeaderboardRow row;

  /// Gold, silver, bronze, then nothing. A podium that goes six deep is not a
  /// podium.
  Color get _rankColour => switch (row.rank) {
        1 => ElevarColors.ball,
        2 => const Color(0xFFC9D3DE),
        3 => const Color(0xFFCD7F32),
        _ => ElevarColors.muted,
      };

  @override
  Widget build(BuildContext context) {
    final avatar = PlayerAvatars.at(row.avatarIndex);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: row.isYou
            ? ElevarColors.ball.withValues(alpha: 0.14)
            : ElevarColors.surfaceRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: row.isYou ? ElevarColors.ball : ElevarColors.ink,
          width: row.isYou ? 3 : 2,
        ),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 34,
            child: Text(
              '${row.rank}',
              style: ElevarType.display(19, color: _rankColour),
            ),
          ),
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: avatar.colour,
              shape: BoxShape.circle,
              border: Border.all(color: ElevarColors.ink, width: 2),
            ),
            child: Text(avatar.emoji, style: const TextStyle(fontSize: 15)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              row.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ElevarType.display(16),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            groupedNumber(row.points),
            style: ElevarType.display(17, color: ElevarColors.ball),
          ),
        ],
      ),
    );
  }
}
