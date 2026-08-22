import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

void main() {
  group('replay round trip', () {
    test('decodes back to what was recorded, on the quantisation grid', () {
      final recorder = ReplayRecorder(
        seed: 0xABCDEF,
        channelCount: 2,
        tickHz: 120,
        sampleEveryTicks: 6,
      );

      final written = <List<double>>[];
      for (var i = 0; i < 400; i++) {
        final sample = <double>[
          quantiseNormalised(0.5 + 0.4 * (i % 40) / 40),
          quantiseNormalised(0.9 - 0.001 * (i % 100)),
        ];
        written.add(sample);
        recorder.addSample(sample);
      }

      final reader = ReplayReader.parse(recorder.finish());
      expect(reader.seed, 0xABCDEF);
      expect(reader.channelCount, 2);
      expect(reader.tickHz, 120);
      expect(reader.sampleCount, 400);

      for (var i = 0; i < 400; i++) {
        expect(reader.valueAt(0, i * 6), closeTo(written[i][0], 1e-9));
        expect(reader.valueAt(1, i * 6), closeTo(written[i][1], 1e-9));
      }
    });

    test('holds the last sample between sample boundaries', () {
      final recorder = ReplayRecorder(
        seed: 1,
        channelCount: 1,
        tickHz: 120,
        sampleEveryTicks: 6,
      )
        ..addSample([quantiseNormalised(0.25)])
        ..addSample([quantiseNormalised(0.75)]);

      final reader = ReplayReader.parse(recorder.finish());
      for (var tick = 0; tick < 6; tick++) {
        expect(reader.valueAt(0, tick), closeTo(quantiseNormalised(0.25), 1e-9));
      }
      for (var tick = 6; tick < 12; tick++) {
        expect(reader.valueAt(0, tick), closeTo(quantiseNormalised(0.75), 1e-9));
      }
      // Past the end, the last sample stands rather than throwing.
      expect(reader.valueAt(0, 9999), closeTo(quantiseNormalised(0.75), 1e-9));
    });

    test('stays small: a three-minute two-human match fits in a few KB', () {
      // 3 min at 20 Hz = 3600 samples x 4 channels. This is the number that
      // decides whether every match can afford to upload its replay.
      final recorder = ReplayRecorder(
        seed: 99,
        channelCount: 4,
        tickHz: 120,
        sampleEveryTicks: 6,
      );
      var x = 0.5;
      for (var i = 0; i < 3600; i++) {
        x += ((i * 7919) % 11 - 5) * 0.002; // small, thumb-like movements
        final v = quantiseNormalised(x.clamp(0.0, 1.0));
        recorder.addSample([v, 0.9, 1 - v, 0.1]);
      }
      final bytes = recorder.finish();
      expect(bytes.length, lessThan(40 * 1024));
    });

    test('rejects a tampered or truncated blob rather than guessing', () {
      final recorder = ReplayRecorder(
        seed: 5,
        channelCount: 1,
        tickHz: 120,
        sampleEveryTicks: 6,
      )..addSample([0.5]);
      final good = recorder.finish();

      expect(() => ReplayReader.parse(good.sublist(0, 10)),
          throwsA(isA<FormatException>()));

      final wrongMagic = List<int>.from(good)..[0] = 0x00;
      expect(() => ReplayReader.parse(wrongMagic),
          throwsA(isA<FormatException>()));

      final wrongVersion = List<int>.from(good)..[4] = 99;
      expect(() => ReplayReader.parse(wrongVersion),
          throwsA(isA<FormatException>()));
    });

    test('quantiseNormalised clamps out-of-range input', () {
      expect(quantiseNormalised(-5), 0);
      expect(quantiseNormalised(5), 1);
    });
  });
}
