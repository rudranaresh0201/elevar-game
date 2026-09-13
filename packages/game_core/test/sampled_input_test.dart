import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

void main() {
  test('a pulse is high for exactly one sample and replays identically', () {
    final input = SampledInput(seed: 7, channelCount: 2);
    final live = <List<double>>[];
    for (var tick = 0; tick < 60; tick++) {
      // The finger lifts between boundaries, on an odd tick.
      if (tick == 13) {
        input
          ..set(0, 0.25)
          ..pulse(1);
      }
      live.add(List<double>.of(input.advance(tick)));
    }

    final highTicks = <int>[
      for (var t = 0; t < live.length; t++)
        if (live[t][1] == 1) t,
    ];
    expect(highTicks, <int>[18, 19, 20, 21, 22, 23]);

    final trigger = EdgeTrigger();
    final fired = <int>[
      for (var t = 0; t < live.length; t++)
        if (trigger.rising(live[t][1])) t,
    ];
    expect(fired, <int>[18]);

    final replay = ReplayReader.parse(input.finish());
    for (var t = 0; t < live.length; t++) {
      expect(replay.sampleAt(t), live[t], reason: 'tick $t');
    }
  });

  test('continuous values are quantised on the live path', () {
    final input = SampledInput(seed: 1, channelCount: 1)..set(0, 0.123456789);
    final value = input.advance(0)[0];
    expect(value, quantiseNormalised(0.123456789));
  });
}
