import 'dart:async';

import 'leaderboard_client.dart';
import 'player_profile.dart';
import 'profile_repository.dart';

/// How the leaderboard screen gets a board.
///
/// Three states, and the screen has to be able to tell them apart, because
/// they call for three different things being said to the player:
///
/// * **Live** — fetched just now.
/// * **Stale** — the network did not answer, so this is the last board we had.
///   Shown, with the age on it. A leaderboard that silently shows yesterday is
///   worse than one that says it is showing yesterday.
/// * **Not connected** — no endpoint is compiled in yet. Not an error and not
///   a spinner: the board genuinely does not exist, and the honest thing is to
///   say so and show the player their own totals instead of an empty list.
enum BoardStatus { live, stale, notConfigured }

class BoardResult {
  const BoardResult({
    required this.snapshot,
    required this.status,
    this.error,
  });

  final LeaderboardSnapshot snapshot;
  final BoardStatus status;

  /// What went wrong, for the "couldn't refresh" line. Never a stack trace on
  /// screen — it is a message a player reads, not a log.
  final String? error;
}

/// Submits this player's totals and returns the board, falling back to the
/// cache when the network will not cooperate.
class LeaderboardService {
  LeaderboardService({
    LeaderboardClient? client,
    ProfileRepository? profiles,
    bool? configured,
  })  : _client = client ?? WebhookLeaderboardClient(),
        _profiles = profiles ?? profileRepository,
        _configured = configured ?? LeaderboardConfig.isConfigured;

  final LeaderboardClient _client;
  final ProfileRepository _profiles;

  /// Whether there is an endpoint to talk to.
  ///
  /// Injectable only so tests can exercise the two paths that exist once one
  /// *is* compiled in. [LeaderboardConfig.endpoint] is a compile-time
  /// constant and is empty in a test run, and a test that worked around that
  /// by reimplementing this method would be testing a copy of it — which is
  /// the version of this that was written first and thrown away.
  final bool _configured;

  Future<BoardResult> refresh() async {
    if (!_configured) {
      return BoardResult(
        snapshot: await _profiles.cachedBoard(),
        status: BoardStatus.notConfigured,
      );
    }

    try {
      final submission = await buildSubmission(profiles: _profiles);
      final board = await _client.submitAndFetch(submission);
      await _profiles.cacheBoard(board);
      return BoardResult(snapshot: board, status: BoardStatus.live);
    } on Object catch (error) {
      // Deliberately catching everything. A socket exception, a DNS failure, a
      // timeout, a webhook that answered with HTML — from this screen's point
      // of view they are one thing, "the board did not arrive", and every one
      // of them has the same correct response.
      return BoardResult(
        snapshot: (await _profiles.cachedBoard()).asStale(),
        status: BoardStatus.stale,
        error: _readable(error),
      );
    }
  }

  static String _readable(Object error) {
    if (error is LeaderboardUnavailable) return error.message;
    if (error is TimeoutException) return 'The board took too long to answer.';
    return 'Could not reach the leaderboard.';
  }
}
