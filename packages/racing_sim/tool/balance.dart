// ignore_for_file: avoid_print
// Measures the difficulty ladder by racing a scripted human of varying skill
// against each bot, a few hundred times.
//
//   dart run tool/balance.dart
//
// The dials live in `lib/src/bot.dart`. These numbers come from a scripted
// opponent, not people — retune against real players before launch.
import 'package:game_core/game_core.dart';
import 'package:racing_sim/racing_sim.dart';

const int racesPerCell = 40;
const List<double> skills = <double>[0.35, 0.60, 0.85, 1.00];

void main() {
  for (final buildTrack in Tracks.all) {
    final track = buildTrack();
    print('');
    print('=== ${track.name} '
        '(${track.totalLength.toStringAsFixed(0)} units/lap, '
        '${RaceRules.standard.laps} laps) ===');
    print('');

    final header = StringBuffer('| bot    |');
    final divider = StringBuffer('|--------|');
    for (final skill in skills) {
      header.write(' skill ${skill.toStringAsFixed(2)} |');
      divider.write('------------|');
    }
    header.write(' avg lap | avg secs | clean |');
    divider.write('---------|----------|-------|');
    print(header);
    print(divider);

    for (final difficulty in BotDifficulty.values) {
      final row = StringBuffer('| ${difficulty.name.padRight(6)} |');

      var lapTickTotal = 0;
      var lapCount = 0;
      var secondsTotal = 0.0;
      var cleanTotal = 0.0;
      var races = 0;

      for (final skill in skills) {
        var humanWins = 0;
        for (var i = 0; i < racesPerCell; i++) {
          final seed = 1000003 * (i + 1) + difficulty.index * 7919;
          final simulation = simulateHeadless(
            seed: seed,
            mode: GameMode.vsBot,
            track: track,
            botDifficulty: difficulty,
            rules: RaceRules.standard,
            p1Controller: proxyDriver(
              side: RacerSide.p1,
              track: track,
              skill: skill,
              seed: seed ^ 0x5EED,
            ),
          );
          if (simulation.state.winner == RacerSide.p1) humanWins++;

          for (final ticks in simulation.state.p1.lapTicks) {
            lapTickTotal += ticks;
            lapCount++;
          }
          secondsTotal += simulation.durationMs / 1000;
          cleanTotal += simulation.p1Cleanliness;
          races++;
        }
        final rate = (humanWins * 100 / racesPerCell).round();
        row.write(' ${'$rate%'.padLeft(10)} |');
      }

      final avgLap = lapCount == 0 ? 0.0 : lapTickTotal / lapCount / 120;
      row.write(' ${avgLap.toStringAsFixed(1).padLeft(7)} |');
      row.write(' ${(secondsTotal / races).toStringAsFixed(0).padLeft(8)} |');
      row.write(
          ' ${'${(cleanTotal / races * 100).round()}%'.padLeft(5)} |');
      print(row);
    }
  }

  print('');
  print('Targets: easy should be beatable by almost anyone, hard beatable by a '
      'good player roughly a third of the time. A row that reads 0% / 100% '
      'with nothing between it is a cliff, not a difficulty.');
}
