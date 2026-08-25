import 'package:game_core/game_core.dart';
import 'package:racing_sim/racing_sim.dart';
import 'package:test/test.dart';

/// Races a scripted human of [skill] against [difficulty] [count] times and
/// returns how often the human won.
double humanWinRate({
  required RaceTrack track,
  required BotDifficulty difficulty,
  required double skill,
  int count = 16,
}) {
  var wins = 0;
  for (var i = 0; i < count; i++) {
    final seed = 1000003 * (i + 1) + difficulty.index * 7919;
    final simulation = simulateHeadless(
      seed: seed,
      mode: GameMode.vsBot,
      track: track,
      botDifficulty: difficulty,
      p1Controller: proxyDriver(
        side: RacerSide.p1,
        track: track,
        skill: skill,
        seed: seed ^ 0x5EED,
      ),
    );
    if (simulation.state.winner == RacerSide.p1) wins++;
  }
  return wins / count;
}

/// Mean lap time in seconds for a bot driving alone.
double soloLapSeconds(RaceTrack track, BotDifficulty difficulty) {
  var ticks = 0;
  var laps = 0;
  for (var i = 0; i < 4; i++) {
    final simulation = simulateHeadless(
      seed: 7777 * (i + 1),
      mode: GameMode.vsBot,
      track: track,
      botDifficulty: difficulty,
      p1Controller: (_, __) => CarInput.coasting,
    );
    for (final lap in simulation.state.p2.lapTicks) {
      ticks += lap;
      laps++;
    }
  }
  return laps == 0 ? double.infinity : ticks / laps / 120;
}

void main() {
  final track = Tracks.dustbowl();

  group('the difficulty ladder is a slope, not a cliff', () {
    test('each difficulty is genuinely quicker than the one below', () {
      final easy = soloLapSeconds(track, BotDifficulty.easy);
      final medium = soloLapSeconds(track, BotDifficulty.medium);
      final hard = soloLapSeconds(track, BotDifficulty.hard);

      expect(medium, lessThan(easy));
      expect(hard, lessThan(medium));

      // And the gaps are small enough that a race is in doubt. When these were
      // 3-10 seconds a lap, every cell of the balance table read 0% or 100%:
      // the quicker driver simply won, always, and difficulty meant nothing.
      expect(easy - hard, lessThan(8.0));
    });

    test('a better player wins more, against every difficulty', () {
      for (final difficulty in BotDifficulty.values) {
        final weak = humanWinRate(
          track: track,
          difficulty: difficulty,
          skill: 0.35,
        );
        final strong = humanWinRate(
          track: track,
          difficulty: difficulty,
          skill: 1.0,
        );
        expect(
          strong,
          greaterThanOrEqualTo(weak),
          reason: 'skill must pay off against ${difficulty.name}',
        );
      }
    });

    test('a given player does worse against a harder bot', () {
      // Measured at 0.6 rather than 0.85 deliberately.
      //
      // This car's performance envelope is narrow — a driver at the limit laps
      // Dustbowl in ~14.4 s and a scruffy one in ~17 s — so by skill 0.85 the
      // proxy is quick enough to beat every difficulty nearly every time, and
      // the ordering between "93%" and "100%" is sampling noise rather than a
      // statement about the bots. At 0.6 the ladder still discriminates:
      // 100% / 40% / 15% on Dustbowl, 100% / 68% / 10% on Sunset Loop.
      const skill = 0.6;
      final vsEasy =
          humanWinRate(track: track, difficulty: BotDifficulty.easy, skill: skill);
      final vsMedium = humanWinRate(
          track: track, difficulty: BotDifficulty.medium, skill: skill);
      final vsHard =
          humanWinRate(track: track, difficulty: BotDifficulty.hard, skill: skill);

      expect(vsEasy, greaterThanOrEqualTo(vsMedium));
      expect(vsMedium, greaterThanOrEqualTo(vsHard));
    });

    test('easy is beatable by a weak player', () {
      final rate = humanWinRate(
        track: track,
        difficulty: BotDifficulty.easy,
        skill: 0.35,
      );
      expect(rate, greaterThan(0.6));
    });

    test('hard is beatable by a strong player but not a mediocre one', () {
      // A bot that cannot be beaten is not hard, it is a wall — and a player
      // who cannot win stops playing.
      expect(
        humanWinRate(track: track, difficulty: BotDifficulty.hard, skill: 1.0),
        greaterThan(0.4),
      );
      expect(
        humanWinRate(track: track, difficulty: BotDifficulty.hard, skill: 0.35),
        lessThan(0.3),
      );
    });
  });

  group('every race terminates', () {
    test('on both circuits, at every difficulty', () {
      for (final buildTrack in Tracks.all) {
        final circuit = buildTrack();
        for (final difficulty in BotDifficulty.values) {
          for (var i = 0; i < 4; i++) {
            final simulation = simulateHeadless(
              seed: 991 * (i + 1) + difficulty.index,
              mode: GameMode.vsBot,
              track: circuit,
              botDifficulty: difficulty,
              p1Controller: proxyDriver(
                side: RacerSide.p1,
                track: circuit,
                skill: 0.7,
                seed: i,
              ),
            );
            expect(
              simulation.isComplete,
              isTrue,
              reason: '${circuit.name} / ${difficulty.name} / seed $i hung',
            );
            expect(simulation.state.winner, isNotNull);
          }
        }
      }
    });

    test('the bot always completes the full distance', () {
      for (final difficulty in BotDifficulty.values) {
        final simulation = simulateHeadless(
          seed: 4321,
          mode: GameMode.vsBot,
          track: track,
          botDifficulty: difficulty,
          p1Controller: (_, __) => CarInput.coasting,
        );
        // Racing a parked car, the bot must get itself round on its own —
        // which is the real test of the unstick rule.
        expect(
          simulation.state.p2.lap,
          RaceRules.standard.laps,
          reason: '${difficulty.name} failed to finish unopposed',
        );
      }
    });

    test('a bot wedged against the scenery frees itself', () {
      // The tyre wall down the pinch is the thing most likely to trap a car.
      // If a bot can get stuck on it, a race becomes a five-minute wait.
      for (final difficulty in BotDifficulty.values) {
        final simulation = simulateHeadless(
          seed: 2024,
          mode: GameMode.vsBot,
          track: track,
          botDifficulty: difficulty,
          p1Controller: (_, __) => const CarInput(steer: 1, throttle: true),
        );
        expect(simulation.state.p2.lap, greaterThan(0));
      }
    });
  });

  group('driving off the track is punished', () {
    test('the bot that makes the most mistakes spends the most time off it', () {
      double offTrackFraction(BotDifficulty difficulty) {
        var off = 0;
        var total = 0;
        for (var i = 0; i < 4; i++) {
          final simulation = simulateHeadless(
            seed: 5150 * (i + 1),
            mode: GameMode.vsBot,
            track: track,
            botDifficulty: difficulty,
            p1Controller: (_, __) => CarInput.coasting,
          );
          off += simulation.state.p2.racingTicks -
              simulation.state.p2.onTrackTicks;
          total += simulation.state.p2.racingTicks;
        }
        return total == 0 ? 0 : off / total;
      }

      // Easy fluffs corner entries an order of magnitude more often than hard,
      // and the grip limit turns that into time on the grass. If this ever
      // reads zero for every difficulty, mistakes have stopped costing
      // anything and the ladder is about to collapse into a top-speed contest.
      // Was 0.01. The grass is more forgiving than it was — deliberately, see
      // `RaceField.dragOnGrass` — so the same mistake now costs less time off
      // the circuit before the car claws its way back on. The ordering below
      // is the part that actually guards the ladder.
      expect(offTrackFraction(BotDifficulty.easy), greaterThan(0.004));
      expect(
        offTrackFraction(BotDifficulty.easy),
        greaterThan(offTrackFraction(BotDifficulty.hard)),
      );
    });
  });
}
