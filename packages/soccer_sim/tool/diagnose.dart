// Prints the numbers that decide whether the game is playable at all, before
// anybody has to look at it. Run with `dart run tool/diagnose.dart`.
//
// Every constant in `field.dart` was set by reading this output, not by
// reasoning about units — the same discipline `docs/CRICKET.md` §5 argues for.
// ignore_for_file: avoid_print

import 'package:game_core/game_core.dart';
import 'package:soccer_sim/soccer_sim.dart';

void main() {
  _flickTravel();
  _shotFromHalfway();
  _searchCost();
  _turnLengths();
  _matchShape();
}

/// How far a flick actually carries, at each power. The single most important
/// table: it decides whether the pitch is the right size.
void _flickTravel() {
  print('--- flick travel (units, out of an 1800-unit pitch) ---');
  print('power   travel   ticks to rest   seconds');
  for (final power in <double>[0.25, 0.5, 0.75, 1.0]) {
    final world = SoccerWorld.kickoff();
    // A disc alone in a corner of the pitch, aimed up the empty side, so the
    // number measures friction and not a collision.
    final disc = world.bodies[0];
    final start = const Vec2(200.0, 1600.0);
    disc
      ..position = start
      ..previousPosition = start;
    for (var i = 1; i < world.bodies.length; i++) {
      world.bodies[i].position = Vec2(4000 + i * 200.0, 4000);
    }
    world.flick(0, const Vec2(0, -1), power);

    var ticks = 0;
    while (!world.atRest && ticks < 2000) {
      world.step(1 / 120);
      ticks++;
    }
    final travel = (disc.position - start).length;
    print('${power.toStringAsFixed(2)}    '
        '${travel.toStringAsFixed(0).padLeft(6)}   '
        '${ticks.toString().padLeft(13)}   '
        '${(ticks / 120).toStringAsFixed(2).padLeft(7)}');
  }
  print('');
}

/// Can a strike actually reach the far goal? If the answer is no the pitch is
/// too long, or the ball is too heavy, and nobody will ever score.
///
/// Measured down an *empty* pitch on purpose. At the kickoff the opposing
/// centre-forward stands directly in front of the ball, so a straight shot off
/// the spot is blocked by design — measuring that instead would report the
/// formation, not the physics.
void _shotFromHalfway() {
  print('--- strike down a clear pitch, from the centre spot ---');
  for (final power in <double>[0.4, 0.6, 0.8, 1.0]) {
    final world = SoccerWorld.kickoff();
    for (var i = 0; i < SoccerWorld.ballIndex; i++) {
      if (i == 3) continue;
      world.bodies[i].position = Vec2(4000 + i * 200.0, 4000);
    }
    const strikerAt = Vec2(
      SoccerField.centreX,
      SoccerField.centreSpotY +
          SoccerField.ballRadius +
          SoccerField.discRadius,
    );
    world.bodies[3]
      ..position = strikerAt
      ..previousPosition = strikerAt;
    world.flick(3, const Vec2(0, -1), power);

    SoccerSide? scorer;
    var ticks = 0;
    while (!world.atRest && ticks < 900) {
      scorer = world.step(1 / 120);
      ticks++;
      if (scorer != null) break;
    }
    print('power ${power.toStringAsFixed(2)}  '
        'scored=${scorer == SoccerSide.p1}  '
        'ball ended y=${world.ball.position.y.toStringAsFixed(0)}  '
        '(goal line is ${SoccerField.topGoalLine.toStringAsFixed(0)})  '
        'after ${(ticks / 120).toStringAsFixed(2)}s');
  }
  print('');
}

/// What one bot turn costs. It is spent in a single frame at the start of the
/// thinking pause, so this number is a frame hitch if it gets large.
void _searchCost() {
  print('--- bot search cost per turn ---');
  for (final difficulty in BotDifficulty.values) {
    final world = SoccerWorld.kickoff();
    final bot = SoccerBot(
      profile: SoccerBotProfile.of(difficulty),
      side: SoccerSide.p2,
      seed: 77,
    );
    final watch = Stopwatch()..start();
    const runs = 20;
    for (var i = 0; i < runs; i++) {
      bot.chooseShot(world, SoccerSide.p2);
    }
    watch.stop();
    print('${difficulty.name.padRight(7)} '
        '${(watch.elapsedMicroseconds / runs / 1000).toStringAsFixed(1)} ms '
        'per turn');
  }
  print('');
}

/// A turn that runs to the resolve cap is a turn that felt broken. This checks
/// how close a real turn gets to it.
void _turnLengths() {
  print('--- turn resolve length, 40 bot-vs-bot turns ---');
  var longest = 0;
  var total = 0;
  var count = 0;
  final simulation = SoccerSimulation(
    seed: 4242,
    mode: GameMode.vsBot,
    botDifficulty: BotDifficulty.medium,
  );
  var lastResolve = 0;
  final human = proxyHuman(side: SoccerSide.p1, skill: 0.7);
  for (var tick = 0; tick < 120 * 60 * 8 && !simulation.isComplete; tick++) {
    final state = simulation.state;
    if (state.phase == SoccerPhase.resolving) {
      lastResolve = state.resolveTicks;
    } else if (lastResolve > 0) {
      if (lastResolve > longest) longest = lastResolve;
      total += lastResolve;
      count++;
      lastResolve = 0;
    }
    simulation.step(
      state.turn == SoccerSide.p1
          ? human(state, tick)
          : SoccerInput.idle,
    );
  }
  print('turns measured: $count');
  print('longest resolve: $longest ticks '
      '(${(longest / 120).toStringAsFixed(2)}s), '
      'cap is ${SoccerRules.standard.maxResolveTicks}');
  if (count > 0) {
    print('mean resolve:    ${(total / count).toStringAsFixed(0)} ticks '
        '(${(total / count / 120).toStringAsFixed(2)}s)');
  }
  print('');
}

/// The shape of a whole match: does it end on goals or on the turn cap, and
/// how long does it take?
void _matchShape() {
  print('--- 12 matches, skill 0.7 human vs medium bot ---');
  var goalEnds = 0;
  var capEnds = 0;
  var totalSeconds = 0.0;
  var totalTurns = 0;
  for (var i = 0; i < 12; i++) {
    final simulation = simulateSoccerHeadless(
      seed: 9000 + i * 37,
      mode: GameMode.vsBot,
      botDifficulty: BotDifficulty.medium,
      p1Controller: proxyHuman(side: SoccerSide.p1, skill: 0.7, seed: i),
    );
    final state = simulation.state;
    if (state.p1Goals >= 3 || state.p2Goals >= 3) {
      goalEnds++;
    } else {
      capEnds++;
    }
    totalSeconds += simulation.durationMs / 1000;
    totalTurns += state.turnsTaken;
    print('  seed ${9000 + i * 37}: ${state.p1Goals}-${state.p2Goals} '
        'in ${state.turnsTaken} turns, '
        '${(simulation.durationMs / 1000).toStringAsFixed(0)}s, '
        'skill ${simulation.normalizedSkill.toStringAsFixed(2)}');
  }
  print('ended on goals: $goalEnds   ended on turn cap: $capEnds');
  print('mean duration:  ${(totalSeconds / 12).toStringAsFixed(0)}s   '
      'mean turns: ${(totalTurns / 12).toStringAsFixed(1)}');
}
