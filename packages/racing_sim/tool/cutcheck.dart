// ignore_for_file: avoid_print
// Is cutting across the infield actually faster than driving round it?
// The answer decides whether the track needs a cut-detection rule at all.
import 'package:racing_sim/racing_sim.dart';

void main() {
  final track = Tracks.dustbowl();
  const dt = 1 / 120.0;

  // Terminal velocity on each surface: where thrust meets drag.
  const onDirt = RaceField.engineForce / RaceField.dragOnTrack;
  const onGrass = RaceField.engineForce / RaceField.dragOnGrass;
  print('terminal speed  dirt ${onDirt.toStringAsFixed(0)}'
      '  grass ${onGrass.toStringAsFixed(0)} units/s');

  // How far can a car carry momentum onto the grass before it bogs down?
  var v = onDirt;
  var carried = 0.0;
  for (var i = 0; i < 120 * 20; i++) {
    v -= v * RaceField.dragOnGrass * dt; // coasting, no throttle
    carried += v * dt;
    if (v < onGrass) break;
  }
  print('coasting from top speed, a car covers '
      '${carried.toStringAsFixed(0)} units of grass before it is slower '
      'than grass terminal');

  // The shortcut: straight across the pinch, bottom straight to top straight.
  final from = track.pointAt(0);
  final to = track.pointAt(track.totalLength / 2);
  final shortcut = (to - from).length;
  final theLongWay = track.totalLength / 2;

  print('');
  print('shortcut across the infield: ${shortcut.toStringAsFixed(0)} units');
  print('the same trip round the track: ${theLongWay.toStringAsFixed(0)} units');

  // Time each, generously: the cutter gets to keep grass terminal the whole
  // way, the racer only manages a realistic 62% of dirt terminal.
  final cutSeconds = shortcut / onGrass;
  final roundSeconds = theLongWay / (onDirt * 0.62);
  print('');
  print('cutting  ~${cutSeconds.toStringAsFixed(1)}s');
  print('racing   ~${roundSeconds.toStringAsFixed(1)}s');
  print(cutSeconds > roundSeconds
      ? 'VERDICT: grass drag alone makes cutting a loss. No cut rule needed.'
      : 'VERDICT: cutting pays. The track needs an explicit cut rule.');
}
