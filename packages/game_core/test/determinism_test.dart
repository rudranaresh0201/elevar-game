import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

void main() {
  group('DeterministicRng', () {
    test('the same seed always produces the same sequence', () {
      final a = DeterministicRng(987654321);
      final b = DeterministicRng(987654321);
      for (var i = 0; i < 5000; i++) {
        expect(a.nextUint32(), b.nextUint32(), reason: 'diverged at draw $i');
      }
    });

    test('different seeds diverge', () {
      final a = DeterministicRng(1);
      final b = DeterministicRng(2);
      final differs = List.generate(64, (_) => a.nextUint32() != b.nextUint32());
      expect(differs.where((d) => d).length, greaterThan(60));
    });

    test('streams from one seed are independent', () {
      // This is what stops a new random call in the serve logic from silently
      // changing how the bot plays.
      final serves = DeterministicRng.stream(42, 1);
      final aim = DeterministicRng.stream(42, 11);
      final first = List.generate(32, (_) => serves.nextUint32());
      final second = List.generate(32, (_) => aim.nextUint32());
      expect(first, isNot(equals(second)));

      final servesAgain = DeterministicRng.stream(42, 1);
      expect(List.generate(32, (_) => servesAgain.nextUint32()), equals(first));
    });

    test('stays inside 32 bits forever', () {
      final rng = DeterministicRng(0xDEADBEEF);
      for (var i = 0; i < 20000; i++) {
        final v = rng.nextUint32();
        expect(v, inInclusiveRange(0, 0xFFFFFFFF));
      }
    });

    test('nextDouble covers [0,1) without escaping it', () {
      final rng = DeterministicRng(7);
      var min = 1.0;
      var max = 0.0;
      for (var i = 0; i < 20000; i++) {
        final v = rng.nextDouble();
        expect(v, greaterThanOrEqualTo(0));
        expect(v, lessThan(1));
        if (v < min) min = v;
        if (v > max) max = v;
      }
      expect(min, lessThan(0.01));
      expect(max, greaterThan(0.99));
    });
  });

  group('FixedLoop', () {
    test('converts real time into whole ticks', () {
      final loop = FixedLoop(tickHz: 120);
      var ticks = 0;
      // A second of 60 fps frames must be exactly a second of 120 Hz ticks.
      for (var frame = 0; frame < 60; frame++) {
        loop.advance(1 / 60, (_) => ticks++);
      }
      expect(ticks, 120);
    });

    test('a stalled frame cannot queue unbounded work', () {
      // Without the cap this is the spiral of death: a long frame queues more
      // steps than the next frame has budget for, forever.
      final loop = FixedLoop(tickHz: 120, maxFrameSeconds: 0.25);
      var ticks = 0;
      loop.advance(10.0, (_) => ticks++);
      expect(ticks, 30);
    });

    test('does not drift when frame times do not divide the step', () {
      // 0.015 s frames against a 0.01 s step never line up, and summing them in
      // binary lands a hair under the exact total. The accumulator must keep
      // that remainder rather than discarding it, so the shortfall stays below
      // one tick forever instead of compounding into seconds of lost match.
      final loop = FixedLoop(tickHz: 100);
      var ticks = 0;
      const frames = 1000;
      for (var i = 0; i < frames; i++) {
        loop.advance(0.015, (_) => ticks++);
      }
      const expected = frames * 0.015 * 100; // 1500 ticks over 15 seconds
      expect((ticks - expected).abs(), lessThanOrEqualTo(1));
    });

    test('advanceTicks ignores wall clock entirely', () {
      final loop = FixedLoop(tickHz: 120);
      final seen = <int>[];
      loop.advanceTicks(5, seen.add);
      expect(seen, [0, 1, 2, 3, 4]);
    });
  });
}
