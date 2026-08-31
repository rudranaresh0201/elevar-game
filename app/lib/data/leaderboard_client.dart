import 'dart:convert';

import 'package:http/http.dart' as http;

import 'player_profile.dart';

/// Where the board comes from.
///
/// Set at build time, never committed:
///
/// ```
/// flutter build apk --release \
///   --dart-define=ELEVAR_LEADERBOARD_WEBHOOK=https://.../webhook/leaderboard
/// ```
///
/// A compile-time constant rather than a runtime setting because an endpoint
/// a player can change is an endpoint a player can point at their own server,
/// and the whole reason the board exists is that its numbers are trusted
/// enough to be redeemed for vouchers.
abstract final class LeaderboardConfig {
  static const String endpoint =
      String.fromEnvironment('ELEVAR_LEADERBOARD_WEBHOOK');

  /// Optional shared secret, sent as `X-Elevar-Key`.
  ///
  /// This is not authentication and is not pretending to be — anything baked
  /// into an APK can be read out of it. It is a doorbell, so the webhook can
  /// drop drive-by traffic without having to reason about it. **The server
  /// must still treat every submitted total as a claim**, and the real defence
  /// is the replay verification in `docs/PLAN.md` §9: the board should be
  /// built from matches the server re-simulated, not from a number the phone
  /// sent.
  static const String key = String.fromEnvironment('ELEVAR_LEADERBOARD_KEY');

  static bool get isConfigured => endpoint.isNotEmpty;
}

/// What the phone tells the board about itself.
class LeaderboardSubmission {
  const LeaderboardSubmission({
    required this.profile,
    required this.lifetimePoints,
    required this.balance,
    required this.streakDays,
    required this.matchesPlayed,
  });

  final PlayerProfile profile;
  final int lifetimePoints;
  final int balance;
  final int streakDays;
  final int matchesPlayed;

  Map<String, Object?> toJson() => <String, Object?>{
        'playerId': profile.playerId,
        'displayName': profile.displayName,
        'avatarIndex': profile.avatarIndex,
        // Lifetime, not balance. Spending points on a voucher should not cost
        // you your place on the board — otherwise the leaderboard and the
        // rewards shop are in direct competition and the player has to choose
        // between them, which is the opposite of what either is for.
        'lifetimePoints': lifetimePoints,
        'balance': balance,
        'streakDays': streakDays,
        'matchesPlayed': matchesPlayed,
        'submittedAt': DateTime.now().toUtc().toIso8601String(),
      };
}

/// Fetches the board.
abstract class LeaderboardClient {
  /// Posts this player's totals and returns the board that comes back.
  ///
  /// Throws on anything that is not a usable board, so the repository can fall
  /// back to its cache and say the board is stale.
  Future<LeaderboardSnapshot> submitAndFetch(LeaderboardSubmission submission);
}

/// The real one: one round trip to a webhook.
///
/// Deliberately a single POST that both submits and returns, rather than a
/// POST and then a GET. It is one request to configure and one to debug, and
/// it means the board a player sees always already contains the match they
/// just finished — which is the moment they actually care where they are.
class WebhookLeaderboardClient implements LeaderboardClient {
  WebhookLeaderboardClient({
    http.Client? httpClient,
    this.endpoint = LeaderboardConfig.endpoint,
    this.apiKey = LeaderboardConfig.key,
    this.timeout = const Duration(seconds: 8),
  }) : _http = httpClient ?? http.Client();

  final http.Client _http;
  final String endpoint;
  final String apiKey;

  /// Short on purpose. The leaderboard is the one screen where a spinner is
  /// the whole experience, and a cached board shown in 8 seconds beats a live
  /// one shown in 30.
  final Duration timeout;

  @override
  Future<LeaderboardSnapshot> submitAndFetch(
    LeaderboardSubmission submission,
  ) async {
    if (endpoint.isEmpty) {
      throw const LeaderboardUnavailable('No leaderboard endpoint configured');
    }

    final response = await _http
        .post(
          Uri.parse(endpoint),
          headers: <String, String>{
            'Content-Type': 'application/json',
            if (apiKey.isNotEmpty) 'X-Elevar-Key': apiKey,
          },
          body: jsonEncode(submission.toJson()),
        )
        .timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LeaderboardUnavailable(
        'Leaderboard webhook returned ${response.statusCode}',
      );
    }

    return parseBoard(response.body, you: submission.profile.playerId);
  }

  /// Turns a webhook response into a board.
  ///
  /// Accepts three shapes, because the thing on the other end is going to be
  /// an automation someone wired up in an afternoon and the app should not be
  /// the reason it has to be rewritten:
  ///
  /// * `{"top": [...], "you": {"rank": n}}`
  /// * `{"rows": [...]}` / `{"leaderboard": [...]}` / `{"data": [...]}`
  /// * a bare `[...]`
  ///
  /// Rank is trusted if present and derived from the ordering if not, so a
  /// sheet that simply returns its rows in order works with no extra columns.
  static LeaderboardSnapshot parseBoard(String body, {required String you}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException catch (error) {
      throw LeaderboardUnavailable('Leaderboard response was not JSON: $error');
    }

    List<Object?>? rawRows;
    int? yourRank;

    if (decoded is List) {
      rawRows = decoded;
    } else if (decoded is Map<String, Object?>) {
      for (final key in const <String>[
        'top',
        'rows',
        'leaderboard',
        'data',
        'results',
      ]) {
        final value = decoded[key];
        if (value is List) {
          rawRows = value;
          break;
        }
      }
      final me = decoded['you'];
      if (me is Map<String, Object?>) {
        final rank = me['rank'];
        if (rank is num) yourRank = rank.toInt();
      }
    }

    if (rawRows == null) {
      throw const LeaderboardUnavailable(
        'Leaderboard response had no rows in it',
      );
    }

    final rows = <LeaderboardRow>[];
    for (var i = 0; i < rawRows.length; i++) {
      final entry = rawRows[i];
      if (entry is! Map<String, Object?>) continue;
      final row = LeaderboardRow.fromJson(entry, i + 1);
      rows.add(row.markedAsYou(row.playerId == you));
    }

    yourRank ??= rows
        .where((row) => row.isYou)
        .map((row) => row.rank)
        .firstOrNull;

    return LeaderboardSnapshot(
      rows: rows,
      yourRank: yourRank,
      fetchedAt: DateTime.now(),
    );
  }
}

/// The board could not be reached, or could not be understood.
class LeaderboardUnavailable implements Exception {
  const LeaderboardUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}
