import 'dart:typed_data';

import 'replay.dart';

/// Feeds a simulation its input on the replay's terms, and records it.
///
/// Every game used to hand-roll this: snap input to the 16-bit grid, only let
/// it change on a sample boundary, hold it in between, record the sample. The
/// four newer games need exactly that plus one thing the continuous games did
/// not — a **discrete action** (a shot, a drop, a dive) that must reach the
/// simulation exactly once, even though the finger lifted between boundaries.
///
/// [pulse] is that action. The channel reads `1` for exactly one sample and `0`
/// again from the next, and the simulation fires on the rising edge. Because
/// the recording holds the same values for the same ticks, the verifier sees
/// the same edge on the same tick — the action is part of the replay, not a
/// side channel next to it.
class SampledInput {
  SampledInput({
    required int seed,
    required this.channelCount,
    this.tickHz = 120,
    this.sampleEveryTicks = ReplayRecorder.defaultSampleEveryTicks,
  })  : _recorder = ReplayRecorder(
          seed: seed,
          channelCount: channelCount,
          tickHz: tickHz,
          sampleEveryTicks: sampleEveryTicks,
        ),
        _held = List<double>.filled(channelCount, 0),
        _pending = List<double?>.filled(channelCount, null),
        _pulseRequested = List<bool>.filled(channelCount, false),
        _pulseLive = List<bool>.filled(channelCount, false);

  final int channelCount;
  final int tickHz;
  final int sampleEveryTicks;

  final ReplayRecorder _recorder;
  final List<double> _held;
  final List<double?> _pending;
  final List<bool> _pulseRequested;
  final List<bool> _pulseLive;

  /// The values the simulation should read on this tick.
  List<double> get held => List<double>.unmodifiable(_held);

  /// Sets a continuous channel. Takes effect on the next sample boundary.
  void set(int channel, double normalised) => _pending[channel] = normalised;

  /// Requests a one-sample action on [channel].
  ///
  /// Any value [set] on the same channel is ignored while the pulse is live —
  /// a pulse channel is a trigger and nothing else.
  void pulse(int channel) => _pulseRequested[channel] = true;

  /// True while a requested pulse has not yet reached the simulation. A view
  /// uses this to avoid asking twice for one gesture.
  bool isPulsePending(int channel) => _pulseRequested[channel];

  /// Call once per tick, *before* stepping the simulation. Returns the input
  /// for this tick.
  List<double> advance(int tick) {
    if (tick % sampleEveryTicks == 0) {
      for (var c = 0; c < channelCount; c++) {
        if (_pulseRequested[c]) {
          _held[c] = 1;
          _pulseRequested[c] = false;
          _pulseLive[c] = true;
        } else if (_pulseLive[c]) {
          _held[c] = 0;
          _pulseLive[c] = false;
        } else if (_pending[c] != null) {
          _held[c] = quantiseNormalised(_pending[c]!);
          _pending[c] = null;
        }
      }
      _recorder.addSample(_held);
    }
    return _held;
  }

  /// Seals the recording.
  Uint8List finish() => _recorder.finish();
}

/// Fires once when a trigger channel crosses from low to high.
///
/// Lives next to [SampledInput] because the two halves have to agree: the
/// runner writes a one-sample `1`, and this is the only correct way to read it.
class EdgeTrigger {
  bool _wasHigh = false;

  /// True on the tick the channel goes high.
  bool rising(double value) {
    final high = value >= 0.5;
    final fired = high && !_wasHigh;
    _wasHigh = high;
    return fired;
  }
}
