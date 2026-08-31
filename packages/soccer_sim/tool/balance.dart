// Win rates for a scripted human of varying skill against each bot
// difficulty, plus how long a match takes and how many goals it contains.
//
// Run with `dart run tool/balance.dart`. Everything here comes from a scripted
// opponent, not from people — **retune against real players before launch**.
// The dials are all in `lib/src/bot.dart`.
// ignore_for_file: avoid_print

import 'package:game_core/game_core.dart';
import 'package:soccer_sim/soccer_sim.dart';

const int matchesPerCell = 32;
const List<double> skills = <double>[0.35, 0.60, 0.85, 1.00];

void main() {
  print('soccer — win rate for the human, $matchesPerCell matches per cell');
  print('');
  final header = StringBuffer('bot     ');
  for (final skill in skills) {
    header.write('  skill ${skill.toStringAsFixed(2)}');
  }
  header.write('   avg goals   avg secs   avg turns');
  print(header);

  for (final difficulty in BotDifficulty.values) {
    final row = StringBuffer(difficulty.name.padRight(8));
    var totalGoals = 0;
    var totalSeconds = 0.0;
    var totalTurns = 0;
    var cells = 0;

    for (final skill in skills) {
      var wins = 0;
      for (var i = 0; i < matchesPerCell; i++) {
        final simulation = simulateSoccerHeadless(
          seed: 0x50CCE4 + i * 7919 + difficulty.index * 104729,
          mode: GameMode.vsBot,
          botDifficulty: difficulty,
          p1Controller: proxyHuman(
            side: SoccerSide.p1,
            skill: skill,
            seed: i * 31 + 5,
          ),
        );
        final state = simulation.state;
        if (state.p1Goals > state.p2Goals) wins++;
        totalGoals += state.p1Goals + state.p2Goals;
        totalSeconds += simulation.durationMs / 1000;
        totalTurns += state.turnsTaken;
        cells++;
      }
      final rate = (100 * wins / matchesPerCell).round();
      row.write('$rate%'.padLeft(11));
    }

    row.write((totalGoals / cells).toStringAsFixed(1).padLeft(12));
    row.write((totalSeconds / cells).toStringAsFixed(0).padLeft(11));
    row.write((totalTurns / cells).toStringAsFixed(0).padLeft(12));
    print(row);
  }

  print('');
  print('A usable ladder is monotonic in both directions: a better human wins');
  print('more against every bot, and a harder bot wins more against every');
  print('human. A cell that breaks that is a difficulty cliff, not a curve.');
}
