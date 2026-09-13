import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:game_core/game_core.dart';

import 'leaderboard_client.dart';
import 'player_profile.dart';
import 'profile_repository.dart';

/// What a board ranks by.
enum BoardMetric {
  /// Lifetime EP, the overall board.
  lifetimePoints,

  /// Highest single-match score: games with a natural high score.
  bestScore,

  /// Matches won against the bot: duel games, where a score line is not a
  /// number worth comparing across players.
  wins,
}

/// One tab on the leaderboard screen.
class BoardTab {
  const BoardTab({
    required this.label,
    required this.metric,
    this.gameSlug,
    this.unit = 'EP',
  });

  final String label;
  final BoardMetric metric;

  /// Null for the overall board.
  final String? gameSlug;

  /// Shown after each row's number.
  final String unit;

  static const BoardTab overall =
      BoardTab(label: 'OVERALL', metric: BoardMetric.lifetimePoints);

  /// Every board, in tab order. Adding a game's board is one line here.
  static const List<BoardTab> all = <BoardTab>[
    overall,
    BoardTab(label: 'FRUIT DROP', gameSlug: 'fruit_drop', metric: BoardMetric.bestScore, unit: 'PTS'),
    BoardTab(label: 'CRICKET', gameSlug: 'cricket', metric: BoardMetric.bestScore, unit: 'RUNS'),
    BoardTab(label: 'FOOTBALL', gameSlug: 'football', metric: BoardMetric.wins, unit: 'WINS'),
    BoardTab(label: 'SHOOTING', gameSlug: 'shooting', metric: BoardMetric.wins, unit: 'WINS'),
    BoardTab(label: 'RACING', gameSlug: 'car_racing', metric: BoardMetric.wins, unit: 'WINS'),
    BoardTab(label: 'PING PONG', gameSlug: 'ping_pong', metric: BoardMetric.wins, unit: 'WINS'),
  ];

  /// What a finished match contributes to its game's board.
  ///
  /// Score is only meaningful where the number is the achievement — runs in
  /// an innings, points in a jar. A win only counts against the bot: with two
  /// people on one phone there is no knowing which of them owns the account.
  static ({int score, bool won}) contribution(GameResult result) => (
        score: switch (result.gameSlug) {
          'fruit_drop' || 'cricket' => result.p1Score,
          _ => 0,
        },
        won: result.mode == GameMode.vsBot && result.humanWon,
      );
}

/// A leaderboard that pushes changes as they happen.
abstract class LiveBoard {
  bool get isConfigured;

  /// Emits the board for [tab] now, and again every time it changes.
  Stream<LeaderboardSnapshot> watch(BoardTab tab);

  /// Sends this player's name, avatar and totals.
  Future<void> syncPlayer(LeaderboardSubmission submission);

  /// Records one finished match.
  Future<void> recordMatch(GameResult result);
}

/// No server compiled in. The screen falls back to its not-connected state.
class DisabledLiveBoard implements LiveBoard {
  const DisabledLiveBoard();

  @override
  bool get isConfigured => false;

  @override
  Stream<LeaderboardSnapshot> watch(BoardTab tab) => const Stream<LeaderboardSnapshot>.empty();

  @override
  Future<void> syncPlayer(LeaderboardSubmission submission) async {}

  @override
  Future<void> recordMatch(GameResult result) async {}
}

/// Turns raw board rows into a ranked snapshot.
///
/// Sorted here even though the query already orders them: a realtime update
/// can land a changed row anywhere in the list, and a board whose order is
/// only as good as the last full fetch is a board that shows the wrong
/// leader for a second after every match.
LeaderboardSnapshot rankRows(
  List<Map<String, dynamic>> rows, {
  required BoardTab tab,
  required String? you,
  int limit = 50,
}) {
  final metricKey = switch (tab.metric) {
    BoardMetric.lifetimePoints => 'lifetime_points',
    BoardMetric.bestScore => 'best_score',
    BoardMetric.wins => 'wins',
  };
  final idKey = tab.gameSlug == null ? 'id' : 'player_id';

  int metricOf(Map<String, dynamic> row) => (row[metricKey] as num?)?.toInt() ?? 0;

  final sorted = rows
      .where((row) => tab.gameSlug == null || row['game_slug'] == tab.gameSlug)
      .where((row) => metricOf(row) > 0)
      .toList()
    ..sort((a, b) {
      final byMetric = metricOf(b).compareTo(metricOf(a));
      if (byMetric != 0) return byMetric;
      // Earlier to the number ranks higher, like a real high-score table.
      return '${a['updated_at']}'.compareTo('${b['updated_at']}');
    });

  final ranked = <LeaderboardRow>[];
  for (var i = 0; i < sorted.length && i < limit; i++) {
    final row = sorted[i];
    final id = '${row[idKey]}';
    ranked.add(LeaderboardRow(
      rank: i + 1,
      playerId: id,
      displayName: (row['display_name'] as String?)?.trim().isNotEmpty == true
          ? (row['display_name'] as String).trim()
          : 'Player',
      points: metricOf(row),
      avatarIndex: ((row['avatar_index'] as num?)?.toInt() ?? 0) % PlayerAvatars.all.length,
      isYou: you != null && id == you,
    ));
  }

  return LeaderboardSnapshot(
    rows: ranked,
    yourRank: ranked.where((r) => r.isYou).map((r) => r.rank).firstOrNull,
    fetchedAt: DateTime.now(),
  );
}

/// The board the app uses. Replaced at start-up when a server is compiled in,
/// and by tests.
LiveBoard liveBoard = const DisabledLiveBoard();

/// Sends the player's name, avatar and totals, in the background. Used at
/// start-up and after a profile edit.
Future<void> syncProfileToBoard() async {
  if (!liveBoard.isConfigured) return;
  try {
    await liveBoard.syncPlayer(await buildSubmission());
  } on Object catch (error) {
    debugPrint('Leaderboard profile sync skipped: $error');
  }
}

/// Pushes a finished match and the player's new totals, in the background.
///
/// Never throws and never blocks the result screen: a player on a train
/// should still see their points. Totals are absolute, so the next match that
/// does reach the server corrects everything a dropped one missed.
Future<void> syncAfterMatch(
  GameResult result,
  Future<LeaderboardSubmission> Function() submission,
) async {
  if (!liveBoard.isConfigured) return;
  try {
    await liveBoard.syncPlayer(await submission());
    await liveBoard.recordMatch(result);
  } on Object catch (error) {
    debugPrint('Leaderboard sync skipped: $error');
  }
}
