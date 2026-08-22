/// How a match was played.
enum GameMode {
  /// Two humans sharing one device.
  local2P,

  /// One human against the in-simulation bot.
  vsBot;

  String get wire => name;

  static GameMode fromWire(String s) =>
      GameMode.values.firstWhere((m) => m.wire == s);
}

/// Bot skill setting. See `pingpong_sim`'s `BotProfile` for what each one
/// actually changes.
enum BotDifficulty {
  easy,
  medium,
  hard;

  String get wire => name;

  static BotDifficulty fromWire(String s) =>
      BotDifficulty.values.firstWhere((d) => d.wire == s);
}

/// Who won.
enum MatchOutcome {
  p1Win,
  p2Win,
  draw;

  String get wire => name;
}

/// The render-free summary of one finished match.
///
/// This is exactly what gets POSTed to `/v1/matches`, and exactly what the
/// headless verifier reproduces from [seed] and [replay]. Every game in the hub
/// produces one of these and nothing else, which is why adding a fourth game
/// requires no change to scoring, sync, or the server.
class GameResult {
  const GameResult({
    required this.gameSlug,
    required this.mode,
    required this.durationMs,
    required this.p1Score,
    required this.p2Score,
    required this.outcome,
    required this.normalizedSkill,
    required this.seed,
    required this.tickCount,
    this.botDifficulty,
    this.replay,
    this.sessionToken,
  });

  final String gameSlug;
  final GameMode mode;
  final BotDifficulty? botDifficulty;
  final int durationMs;
  final int p1Score;
  final int p2Score;
  final MatchOutcome outcome;

  /// Skill on a 0..1 scale, defined per game but comparable across games.
  ///
  /// This is the universal translator that lets one server-side points formula
  /// pay out fairly for a ping pong rally and a puzzle solve alike — the
  /// formula never learns what game it is scoring.
  final double normalizedSkill;

  /// The server-issued nonce that seeded the simulation.
  final int seed;

  /// Simulation ticks elapsed. With the tick rate, this is the authoritative
  /// match duration — wall-clock time can be tampered with, tick count cannot
  /// exceed what the recorded input log actually contains.
  final int tickCount;

  /// Compressed input log, replayable by `ReplayReader`.
  final List<int>? replay;

  /// Signed match-session token obtained from the server (possibly while the
  /// device was last online — see the token pool in `docs/PLAN.md` §10).
  final String? sessionToken;

  /// True when the human player (always P1) won.
  bool get humanWon => outcome == MatchOutcome.p1Win;

  Map<String, Object?> toJson() => {
        'gameSlug': gameSlug,
        'mode': mode.wire,
        if (botDifficulty != null) 'botDifficulty': botDifficulty!.wire,
        'durationMs': durationMs,
        'p1Score': p1Score,
        'p2Score': p2Score,
        'outcome': outcome.wire,
        'normalizedSkill': normalizedSkill,
        'seed': seed,
        'tickCount': tickCount,
        if (sessionToken != null) 'sessionToken': sessionToken,
      };

  @override
  String toString() => 'GameResult($gameSlug $p1Score-$p2Score, ${outcome.wire}, '
      'skill ${normalizedSkill.toStringAsFixed(2)})';
}
