// ignore_for_file: avoid_print
import 'package:game_core/game_core.dart';
import 'package:racing_sim/racing_sim.dart';

/// Can a player who goes off actually get back on?
///
/// This exists because the answer used to be no, and no test caught it. Driving
/// deliberately into the scenery and then trying to recover the way a person
/// would is not something a unit test expresses well, but it is exactly what
/// broke: full throttle and full lock for six seconds left the car doing
/// **0.6 units/s, travelling backwards**.
RaceSimulation _launch() {
  final sim = RaceSimulation(
    seed: 1,
    mode: GameMode.vsBot,
    botDifficulty: BotDifficulty.easy,
    track: Tracks.dustbowl(),
  );
  for (var i = 0; i < 400; i++) {
    sim.step(const RaceInput(p1: CarInput(throttle: true)));
  }
  return sim;
}

void _driveOff(RaceSimulation sim, {int ticks = 260}) {
  for (var i = 0; i < ticks; i++) {
    sim.step(const RaceInput(p1: CarInput(throttle: true, steer: -1)));
  }
}

/// Steers back towards the racing line the way a player looking at the screen
/// would, rather than holding one direction forever.
void _driveHome(RaceSimulation sim, int ticks) {
  final track = sim.track;
  final car = sim.state.p1;
  for (var i = 0; i < ticks; i++) {
    final projection = track.project(car.position, hintSegment: car.segmentHint);
    // Which way is the road, relative to where the nose is pointing?
    final toRoad = (projection.closest - car.position).normalized;
    final steer = toRoad.dot(car.right) > 0.08
        ? 1
        : (toRoad.dot(car.right) < -0.08 ? -1 : 0);
    sim.step(RaceInput(p1: CarInput(throttle: true, steer: steer)));
  }
}

void main() {
  print('--- 1. off into the grass, then steer back to the road ---');
  var sim = _launch();
  _driveOff(sim);
  var car = sim.state.p1;
  print('  stranded on ${car.surface.name} at ${car.speed.toStringAsFixed(1)} units/s');
  for (var s = 1; s <= 5; s++) {
    _driveHome(sim, 120);
    print('  +${s}s: ${car.surface.name} @ ${car.speed.toStringAsFixed(1)} units/s'
        '${car.rescues > 0 ? '  (rescued x${car.rescues})' : ''}');
    if (car.onTrack && car.speed > 100) break;
  }
  print(car.onTrack
      ? '  RECOVERED under the player\'s own steam.'
      : '  STILL OFF.');

  print('');
  print('--- 2. beached: driven off and then abandoned ---');
  sim = _launch();
  _driveOff(sim);
  car = sim.state.p1;
  for (var s = 1; s <= 6; s++) {
    for (var i = 0; i < 120; i++) {
      sim.step(const RaceInput(p1: CarInput()));
    }
    print('  +${s}s coasting: ${car.surface.name} @ '
        '${car.speed.toStringAsFixed(1)} units/s'
        '${car.rescues > 0 ? '  MARSHALLED x${car.rescues}' : ''}');
    if (car.rescues > 0) break;
  }
  print(car.rescues > 0
      ? '  The marshals picked it up and it is back on the line.'
      : '  NOBODY CAME. Still beached.');
}
