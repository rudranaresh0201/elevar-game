// ignore_for_file: avoid_print
import 'package:cricket_sim/cricket_sim.dart';
import 'package:game_core/game_core.dart';

/// What actually happens over a lot of deliveries.
///
/// A cricket simulation can pass every unit test and still produce scores no
/// cricket match has ever produced. This prints the shape of the thing —
/// scores, dismissals, where the runs come from — so the balance can be read
/// rather than assumed.
void main() {
  for (final difficulty in BotDifficulty.values) {
    print('=== vs ${difficulty.name.toUpperCase()} ===');
    for (final skill in <double>[0.3, 0.6, 0.9]) {
      _sample(difficulty: difficulty, skill: skill, matches: 150);
    }
    print('');
  }
}

void _sample({
  required BotDifficulty difficulty,
  required double skill,
  required int matches,
}) {
  var humanRuns = 0;
  var botRuns = 0;
  var humanWins = 0;
  var ties = 0;
  var dots = 0;
  var fours = 0;
  var sixes = 0;
  var singles = 0;
  var caught = 0;
  var balls = 0;
  var totalTicks = 0;

  for (var i = 0; i < matches; i++) {
    final simulation = simulateHeadless(
      seed: 1000 + i * 37,
      mode: GameMode.vsBot,
      botDifficulty: difficulty,
      striker: proxyBatter(skill: skill, seed: 500 + i),
      // The bot's innings is bowled by the *human*, so leaving this out meant
      // the bot faced a fixed, identical delivery on every ball of every match
      // — and half the balance table was measuring nothing at all.
      bowler: proxyBowler(skill: skill, seed: 700 + i),
    );
    final state = simulation.state;

    humanRuns += state.runsFor(CricketSide.p1);
    botRuns += state.runsFor(CricketSide.p2);
    if (state.tied) {
      ties++;
    } else if (state.winner == CricketSide.p1) {
      humanWins++;
    }
    totalTicks += simulation.tick;

    for (final innings in <InningsState?>[state.first, state.second]) {
      if (innings == null) continue;
      for (final ball in innings.timeline) {
        balls++;
        if (ball == -1) continue;
        if (ball == 0) dots++;
        if (ball == 4) fours++;
        if (ball == 6) sixes++;
        if (ball >= 1 && ball <= 3) singles++;
      }
    }
    // Dismissal kinds are not kept on the timeline, so count them from the
    // wicket tallies instead.
    caught += state.wicketsFor(CricketSide.p1) + state.wicketsFor(CricketSide.p2);
  }

  final avgHuman = (humanRuns / matches).toStringAsFixed(1);
  final avgBot = (botRuns / matches).toStringAsFixed(1);
  final winPct = (humanWins * 100 / matches).round();
  final tiePct = (ties * 100 / matches).round();
  final secs = (totalTicks / matches / 120).round();

  print('  skill ${skill.toStringAsFixed(1)}  '
      'human ${avgHuman.padLeft(5)}  bot ${avgBot.padLeft(5)}  '
      'win ${winPct.toString().padLeft(3)}%  tie ${tiePct.toString().padLeft(2)}%  '
      '${secs}s   '
      'dots ${_pct(dots, balls)}  1-3 ${_pct(singles, balls)}  '
      '4s ${_pct(fours, balls)}  6s ${_pct(sixes, balls)}  '
      'wkts ${(caught / matches).toStringAsFixed(1)}');
}

String _pct(int n, int total) =>
    total == 0 ? '  0%' : '${(n * 100 / total).round().toString().padLeft(3)}%';
