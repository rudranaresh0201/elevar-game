import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:game_core/game_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'leaderboard_client.dart';
import 'live_board.dart';
import 'player_profile.dart';

/// Where the board lives.
///
/// Compiled in, never committed. Put them in `app/elevar.env.json` (ignored
/// by git) and build with:
///
/// ```
/// flutter build apk --release --dart-define-from-file=elevar.env.json
/// ```
///
/// Either kind of client key works: the newer `sb_publishable_…` key or the
/// legacy `anon` JWT. Both are designed to ship inside apps: it grants only what the row
/// security rules in `backend/supabase/schema.sql` allow, which is reading
/// boards and calling the two write functions as yourself.
abstract final class SupabaseConfig {
  static const String url = String.fromEnvironment('ELEVAR_SUPABASE_URL');
  static const String anonKey = String.fromEnvironment('ELEVAR_SUPABASE_ANON_KEY');

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}

/// Connects to Supabase if it is compiled in. Safe to call offline: nothing
/// here needs the network until the first board or sync.
Future<void> startLiveBoard() async {
  if (!SupabaseConfig.isConfigured) return;
  try {
    await Supabase.initialize(url: SupabaseConfig.url, publishableKey: SupabaseConfig.anonKey);
    liveBoard = SupabaseLiveBoard(Supabase.instance.client);
  } on Object catch (error) {
    debugPrint('Leaderboard unavailable: $error');
  }
}

/// The realtime leaderboard, on Supabase.
///
/// Every device signs in anonymously the first time it needs to — no sign-up
/// screen, no email — and that account is what owns its row. A real login
/// can later be linked to the same account, so points earned before signing
/// in are not lost.
class SupabaseLiveBoard implements LiveBoard {
  SupabaseLiveBoard(this._client);

  final SupabaseClient _client;
  Future<String>? _signingIn;

  @override
  bool get isConfigured => true;

  Future<String> _userId() {
    final current = _client.auth.currentUser;
    if (current != null) return Future<String>.value(current.id);
    return _signingIn ??= _client.auth.signInAnonymously().then((response) {
      final id = response.user?.id;
      if (id == null) throw StateError('Anonymous sign-in returned no user');
      return id;
    }).whenComplete(() => _signingIn = null);
  }

  @override
  Stream<LeaderboardSnapshot> watch(BoardTab tab) async* {
    String? you;
    try {
      you = await _userId();
    } on Object catch (error) {
      // Still show the board; just without a highlighted row.
      debugPrint('Leaderboard sign-in failed: $error');
    }

    final Stream<List<Map<String, dynamic>>> rows;
    if (tab.gameSlug == null) {
      rows = _client
          .from('players')
          .stream(primaryKey: <String>['id'])
          .order('lifetime_points', ascending: false)
          .limit(50);
    } else {
      rows = _client
          .from('game_records')
          .stream(primaryKey: <String>['player_id', 'game_slug'])
          .eq('game_slug', tab.gameSlug!)
          .order(tab.metric == BoardMetric.wins ? 'wins' : 'best_score', ascending: false)
          .limit(50);
    }

    await for (final batch in rows) {
      yield rankRows(batch, tab: tab, you: you);
    }
  }

  @override
  Future<void> syncPlayer(LeaderboardSubmission submission) async {
    await _userId();
    await _client.rpc<void>('sync_player', params: <String, Object?>{
      'p_device_id': submission.profile.playerId,
      'p_display_name': submission.profile.displayName,
      'p_avatar_index': submission.profile.avatarIndex,
      'p_lifetime_points': submission.lifetimePoints,
      'p_matches_played': submission.matchesPlayed,
      'p_streak_days': submission.streakDays,
    });
  }

  @override
  Future<void> recordMatch(GameResult result) async {
    await _userId();
    final contribution = BoardTab.contribution(result);
    await _client.rpc<void>('record_match', params: <String, Object?>{
      'p_game_slug': result.gameSlug,
      'p_score': contribution.score,
      'p_won': contribution.won,
    });
  }
}
