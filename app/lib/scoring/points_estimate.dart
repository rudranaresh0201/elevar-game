import 'dart:math' as math;

import 'package:game_core/game_core.dart';

/// A breakdown of what a match is worth, in Elevar Points.
class PointsEstimate {
  const PointsEstimate({
    required this.completion,
    required this.outcome,
    required this.performance,
    required this.streakMultiplier,
    required this.diminishing,
    required this.awarded,
    required this.cappedByDailyLimit,
  });

  final int completion;
  final int outcome;
  final int performance;
  final double streakMultiplier;
  final double diminishing;
  final int awarded;
  final bool cappedByDailyLimit;

  int get subtotal => completion + outcome + performance;
}

/// Estimates the payout for a finished match.
///
/// **This is an estimate, and deliberately so.** The authoritative formula
/// lives on the server and nowhere else, for two reasons. It cannot be
/// tampered with there, which matters once points buy vouchers. And it can be
/// retuned there without shipping an app update — the whole reward economy is a
/// number you will want to change after watching real players, not before.
///
/// The client computes this only so the result screen has something to animate
/// immediately instead of a spinner. When the match syncs, the server's number
/// replaces it.
PointsEstimate estimatePoints(
  GameResult result, {
  int matchesAlreadyToday = 0,
  int streakDays = 1,
  int pointsAlreadyToday = 0,
}) {
  const completion = 10;
  const dailyCap = 300;

  final outcome = switch (result.mode) {
    // Only one of the two players is signed in, and there is no way to know
    // which human held which paddle. Paying the "winner" would be meaningless
    // and trivially farmed, so shared-screen play pays for taking part.
    GameMode.local2P => 12,
    GameMode.vsBot => result.humanWon
        ? (15 *
                switch (result.botDifficulty!) {
                  BotDifficulty.easy => 1.0,
                  BotDifficulty.medium => 1.5,
                  BotDifficulty.hard => 2.2,
                })
            .round()
        : 4,
  };

  final performance = (result.normalizedSkill * 15).round();

  final streakMultiplier = switch (streakDays) {
    >= 30 => 1.5,
    >= 14 => 1.3,
    >= 7 => 1.2,
    >= 3 => 1.1,
    _ => 1.0,
  };

  // Diminishing returns are what bound your voucher liability: they put a hard
  // ceiling on what one account can mint in a day, however long it grinds.
  final nth = matchesAlreadyToday + 1;
  final diminishing = switch (nth) {
    <= 5 => 1.0,
    <= 10 => 0.5,
    _ => 0.1,
  };

  final raw = ((completion + outcome + performance) *
          streakMultiplier *
          diminishing)
      .floor();

  final remaining = math.max(0, dailyCap - pointsAlreadyToday);
  final awarded = math.min(raw, remaining);

  return PointsEstimate(
    completion: completion,
    outcome: outcome,
    performance: performance,
    streakMultiplier: streakMultiplier,
    diminishing: diminishing,
    awarded: awarded,
    cappedByDailyLimit: awarded < raw,
  );
}
