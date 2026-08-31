import 'package:design_system/design_system.dart';
import 'package:flutter/painting.dart';

/// Who is holding the phone.
///
/// The hub was per-*device* until this existed: one balance, no name, nothing
/// to put on a board. A leaderboard needs three things and this is all three —
/// a stable id the server can key on, a name a person chose, and something to
/// draw next to it.
class PlayerProfile {
  const PlayerProfile({
    required this.playerId,
    required this.displayName,
    required this.avatarIndex,
    required this.createdAt,
  });

  /// Generated once on this device and never changed.
  ///
  /// Not an account. Elevar has no login yet, and inventing one before there
  /// is a server to log into would mean a sign-up wall in front of a game — the
  /// most reliable way to lose somebody who arrived from an Instagram link. The
  /// id is what a real account will later be *attached to*, so the points a
  /// player earns before signing in are not lost when they do.
  final String playerId;

  final String displayName;

  /// Index into [PlayerAvatars.all].
  final int avatarIndex;

  final DateTime createdAt;

  Color get colour => PlayerAvatars.all[avatarIndex].colour;
  String get emoji => PlayerAvatars.all[avatarIndex].emoji;

  /// True while the player is still using the handle they were given.
  ///
  /// Worth knowing: a board full of "Player 4821" is a board nobody wants to
  /// be on, so the profile screen nudges exactly these players and leaves
  /// everyone else alone.
  bool get hasDefaultName => displayName.startsWith(defaultNamePrefix);

  static const String defaultNamePrefix = 'Player ';

  PlayerProfile copyWith({String? displayName, int? avatarIndex}) =>
      PlayerProfile(
        playerId: playerId,
        displayName: displayName ?? this.displayName,
        avatarIndex: avatarIndex ?? this.avatarIndex,
        createdAt: createdAt,
      );
}

/// One of the pickable avatars.
class PlayerAvatar {
  const PlayerAvatar(this.emoji, this.colour);

  final String emoji;
  final Color colour;
}

/// The avatar set.
///
/// Emoji rather than drawn art, for a reason that is practical rather than
/// lazy: they render on every platform including the web build, they cost no
/// asset bytes, and they can be changed without an app release once the
/// server owns the profile.
abstract final class PlayerAvatars {
  static const List<PlayerAvatar> all = <PlayerAvatar>[
    PlayerAvatar('⚽', SoccerColors.turf),
    PlayerAvatar('🔥', ElevarColors.p1),
    PlayerAvatar('⚡', ElevarColors.ball),
    PlayerAvatar('🏏', ElevarColors.table),
    PlayerAvatar('🏎️', RacingColors.carP2),
    PlayerAvatar('🏓', ElevarColors.p2),
    PlayerAvatar('👟', SoccerColors.discP2),
    PlayerAvatar('🥇', ElevarColors.ball),
  ];

  static PlayerAvatar at(int index) => all[index % all.length];
}

/// One row of the board.
class LeaderboardRow {
  const LeaderboardRow({
    required this.rank,
    required this.playerId,
    required this.displayName,
    required this.points,
    required this.avatarIndex,
    this.isYou = false,
  });

  final int rank;
  final String playerId;
  final String displayName;
  final int points;
  final int avatarIndex;

  /// Set by the repository rather than trusted from the wire, so a server that
  /// forgets the flag still highlights the right row.
  final bool isYou;

  LeaderboardRow markedAsYou(bool value) => LeaderboardRow(
        rank: rank,
        playerId: playerId,
        displayName: displayName,
        points: points,
        avatarIndex: avatarIndex,
        isYou: value,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'rank': rank,
        'playerId': playerId,
        'displayName': displayName,
        'points': points,
        'avatarIndex': avatarIndex,
      };

  /// Deliberately tolerant.
  ///
  /// The board is going to be served by whatever Elevar already runs — an n8n
  /// webhook over a Google Sheet, most likely — and the exact key casing of
  /// that response is not worth an app release to agree on. Anything missing
  /// degrades to something displayable rather than throwing, because a
  /// leaderboard that renders one wrong name is better than one that shows an
  /// error.
  factory LeaderboardRow.fromJson(Map<String, Object?> json, int fallbackRank) {
    int readInt(List<String> keys, int fallback) {
      for (final key in keys) {
        final value = json[key];
        if (value is int) return value;
        if (value is num) return value.toInt();
        if (value is String) {
          final parsed = int.tryParse(value.trim());
          if (parsed != null) return parsed;
        }
      }
      return fallback;
    }

    String readString(List<String> keys, String fallback) {
      for (final key in keys) {
        final value = json[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
      return fallback;
    }

    return LeaderboardRow(
      rank: readInt(<String>['rank', 'position'], fallbackRank),
      playerId: readString(
        <String>['playerId', 'player_id', 'id'],
        'unknown-$fallbackRank',
      ),
      displayName: readString(
        <String>['displayName', 'display_name', 'name', 'player'],
        'Player',
      ),
      points: readInt(<String>['points', 'ep', 'score', 'total'], 0),
      avatarIndex: readInt(<String>['avatarIndex', 'avatar'], 0) %
          PlayerAvatars.all.length,
    );
  }
}

/// A board, and how fresh it is.
class LeaderboardSnapshot {
  const LeaderboardSnapshot({
    required this.rows,
    required this.yourRank,
    required this.fetchedAt,
    this.stale = false,
  });

  static const LeaderboardSnapshot empty = LeaderboardSnapshot(
    rows: <LeaderboardRow>[],
    yourRank: null,
    fetchedAt: null,
  );

  final List<LeaderboardRow> rows;

  /// Your position, which may be well outside [rows] on a large board.
  final int? yourRank;

  final DateTime? fetchedAt;

  /// True when this came out of the cache because the network did not answer.
  /// Surfaced in the UI rather than hidden: a board silently showing yesterday
  /// is worse than one that says so.
  final bool stale;

  bool get isEmpty => rows.isEmpty;

  LeaderboardSnapshot asStale() => LeaderboardSnapshot(
        rows: rows,
        yourRank: yourRank,
        fetchedAt: fetchedAt,
        stale: true,
      );
}
