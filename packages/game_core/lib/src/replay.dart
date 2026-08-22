import 'dart:typed_data';

/// Wire format magic: "ELVR".
const int _magic = 0x454C5652;
const int _formatVersion = 1;

/// Snaps a normalised `[0, 1]` value onto the replay's 16-bit grid.
///
/// The live game must feed the simulation *these* values, not raw touch
/// positions. If the running match used full-precision input and only the
/// recording were quantised, a replay would diverge from the match it claims to
/// verify — slowly at first, then completely, because a simulation amplifies
/// tiny differences. Quantising on the way in costs nothing: the grid is finer
/// than 0.02 of a field unit.
double quantiseNormalised(double value) {
  final clamped = value < 0 ? 0.0 : (value > 1 ? 1.0 : value);
  return (clamped * 65535).round() / 65535.0;
}

/// Records the human input stream of a match in a form the server can replay.
///
/// The whole anti-cheat story in `docs/PLAN.md` §9 rests on this file being
/// small enough to always upload and complete enough to re-derive the score
/// from. Three things make it small:
///
/// * **Only human input is recorded.** The bot lives inside the simulation and
///   is driven by the seeded RNG, so its movement is reproducible for free —
///   and a tampered client cannot claim a bot played worse than it did.
/// * **Positions are quantised** to 16 bits of a normalised 0..1 field
///   coordinate, roughly 0.015 px of a 1000-unit field. Far finer than a thumb.
/// * **Samples are delta-encoded as varints.** A paddle moves a few units
///   between samples, so almost every delta fits in one byte.
///
/// A three-minute match costs about 4 KB before gzip.
class ReplayRecorder {
  ReplayRecorder({
    required this.seed,
    required this.channelCount,
    required this.tickHz,
    required this.sampleEveryTicks,
  })  : assert(channelCount > 0),
        assert(sampleEveryTicks > 0),
        _previous = List<int>.filled(channelCount, 0);

  final int seed;

  /// One channel per recorded scalar — a two-human pong match records
  /// `p1.x, p1.y, p2.x, p2.y`, so four.
  final int channelCount;

  final int tickHz;

  /// Input is sampled at `tickHz / sampleEveryTicks`. At 120 Hz with a stride
  /// of 6 that is 20 Hz, which is finer than a human can move a thumb and six
  /// times cheaper to store than sampling every tick.
  final int sampleEveryTicks;

  final List<int> _previous;
  final BytesBuilder _body = BytesBuilder(copy: false);
  int _sampleCount = 0;

  int get sampleCount => _sampleCount;

  /// Records one sample. Each value must be a normalised field coordinate in
  /// `[0, 1]`; values outside are clamped.
  void addSample(List<double> normalisedValues) {
    assert(normalisedValues.length == channelCount);
    for (var c = 0; c < channelCount; c++) {
      final q = _quantise(normalisedValues[c]);
      _writeVarint(_body, _zigzag(q - _previous[c]));
      _previous[c] = q;
    }
    _sampleCount++;
  }

  /// Seals the recording into its final byte form.
  Uint8List finish() {
    final header = ByteData(20);
    header.setUint32(0, _magic);
    header.setUint8(4, _formatVersion);
    header.setUint8(5, channelCount);
    header.setUint16(6, tickHz);
    header.setUint16(8, sampleEveryTicks);
    header.setUint32(10, _sampleCount);
    header.setUint16(14, 0); // reserved
    // Seed is written as two 32-bit halves so the format stays exact on the web,
    // where a single 64-bit int would lose precision.
    header.setUint32(16, seed & 0xFFFFFFFF);

    final seedHigh = ByteData(4)..setUint32(0, (seed >> 32) & 0xFFFFFFFF);

    final out = BytesBuilder(copy: false)
      ..add(header.buffer.asUint8List())
      ..add(seedHigh.buffer.asUint8List())
      ..add(_body.toBytes());
    return out.toBytes();
  }

  static int _quantise(double v) {
    final clamped = v < 0 ? 0.0 : (v > 1 ? 1.0 : v);
    return (clamped * 65535).round();
  }

  /// Default input sampling stride: 20 Hz against a 120 Hz simulation. Finer
  /// than a thumb can move, six times cheaper to store than every tick.
  static const int defaultSampleEveryTicks = 6;

  static int _zigzag(int n) => n >= 0 ? n * 2 : -n * 2 - 1;

  static void _writeVarint(BytesBuilder out, int value) {
    var v = value;
    while (v >= 0x80) {
      out.addByte((v & 0x7F) | 0x80);
      v >>= 7;
    }
    out.addByte(v);
  }
}

/// Decodes a [ReplayRecorder] blob back into per-tick input.
class ReplayReader {
  ReplayReader._({
    required this.seed,
    required this.channelCount,
    required this.tickHz,
    required this.sampleEveryTicks,
    required List<Float64List> channels,
  }) : _channels = channels;

  /// Parses [bytes], throwing [FormatException] on anything malformed.
  ///
  /// Malformed input here means a tampered or truncated upload, so this is
  /// deliberately strict rather than lenient.
  factory ReplayReader.parse(List<int> bytes) {
    final data = Uint8List.fromList(bytes);
    if (data.length < 24) {
      throw const FormatException('Replay too short to contain a header');
    }
    final view = ByteData.sublistView(data);
    if (view.getUint32(0) != _magic) {
      throw const FormatException('Not an Elevar replay');
    }
    final version = view.getUint8(4);
    if (version != _formatVersion) {
      throw FormatException('Unsupported replay version $version');
    }
    final channelCount = view.getUint8(5);
    final tickHz = view.getUint16(6);
    final sampleEveryTicks = view.getUint16(8);
    final sampleCount = view.getUint32(10);
    final seedLow = view.getUint32(16);
    final seedHigh = view.getUint32(20);
    final seed = (seedHigh << 32) | seedLow;

    if (channelCount == 0 || sampleEveryTicks == 0) {
      throw const FormatException('Replay header describes no input');
    }

    final channels = List<Float64List>.generate(
      channelCount,
      (_) => Float64List(sampleCount),
    );
    final previous = List<int>.filled(channelCount, 0);

    var offset = 24;
    for (var s = 0; s < sampleCount; s++) {
      for (var c = 0; c < channelCount; c++) {
        final decoded = _readVarint(data, offset);
        offset = decoded.nextOffset;
        final value = previous[c] + _unzigzag(decoded.value);
        previous[c] = value;
        channels[c][s] = value / 65535.0;
      }
    }

    return ReplayReader._(
      seed: seed,
      channelCount: channelCount,
      tickHz: tickHz,
      sampleEveryTicks: sampleEveryTicks,
      channels: channels,
    );
  }

  final int seed;
  final int channelCount;
  final int tickHz;
  final int sampleEveryTicks;
  final List<Float64List> _channels;

  int get sampleCount => _channels.isEmpty ? 0 : _channels.first.length;

  /// Total simulation ticks this recording covers.
  int get tickCount => sampleCount * sampleEveryTicks;

  /// The value of [channel] in effect at [tick].
  ///
  /// Between samples the last value is held, exactly as the live simulation
  /// held it — interpolating instead would produce a different match.
  double valueAt(int channel, int tick) {
    if (sampleCount == 0) return 0;
    var index = tick ~/ sampleEveryTicks;
    if (index < 0) index = 0;
    if (index >= sampleCount) index = sampleCount - 1;
    return _channels[channel][index];
  }

  /// All channel values in effect at [tick].
  List<double> sampleAt(int tick) =>
      List<double>.generate(channelCount, (c) => valueAt(c, tick));

  static int _unzigzag(int n) => n.isEven ? n ~/ 2 : -((n + 1) ~/ 2);

  static ({int value, int nextOffset}) _readVarint(Uint8List data, int offset) {
    var result = 0;
    var shift = 0;
    var i = offset;
    while (true) {
      if (i >= data.length) {
        throw const FormatException('Replay truncated mid-varint');
      }
      final byte = data[i];
      i++;
      result |= (byte & 0x7F) << shift;
      if (byte & 0x80 == 0) break;
      shift += 7;
      if (shift > 35) {
        throw const FormatException('Replay varint overflows');
      }
    }
    return (value: result, nextOffset: i);
  }
}
