import 'package:game_core/game_core.dart';

/// How hard the round is: the jar's width, the score to reach, and how many
/// fruit you get to reach it with.
///
/// The first build handed out unlimited fruit, so every target fell to
/// patience. A drop budget is what Candy Crush's move limit and Bubble
/// Shooter's ball count are: it turns "keep going" into "every drop counts".
enum JarSize {
  wide(width: 700, target: 250, drops: 60),
  standard(width: 640, target: 400, drops: 70),
  narrow(width: 580, target: 500, drops: 70);

  const JarSize({required this.width, required this.target, required this.drops});

  final double width;
  final int target;
  final int drops;

  static JarSize of(BotDifficulty d) => switch (d) {
        BotDifficulty.easy => JarSize.wide,
        BotDifficulty.medium => JarSize.standard,
        BotDifficulty.hard => JarSize.narrow,
      };

  BotDifficulty get difficulty => switch (this) {
        JarSize.wide => BotDifficulty.easy,
        JarSize.standard => BotDifficulty.medium,
        JarSize.narrow => BotDifficulty.hard,
      };
}

/// The eleven fruits, smallest first.
abstract final class Fruits {
  static const List<double> radii = <double>[
    22, 30, 38, 47, 57, 68, 80, 94, 110, 128, 150,
  ];

  static const int count = 11;
  static const int watermelon = 10;

  /// Only the five smallest are ever handed to the player.
  static const List<int> dropWeights = <int>[30, 26, 20, 14, 10];

  /// Points for *making* a fruit of [tier] by merging: 1, 3, 6, 10…
  static int pointsFor(int tier) => tier * (tier + 1) ~/ 2;

  /// Two watermelons pop entirely, for this on top.
  static const int watermelonBonus = 100;

  /// Paid per unused drop when the target is reached early.
  static const int dropBonus = 10;
}

enum RoundEnd { targetHit, outOfDrops, jarFull }

class Fruit {
  Fruit({
    required this.id,
    required this.tier,
    required this.position,
    required this.bornTick,
    double growFrom = 1,
  })  : previous = position,
        grow = growFrom;

  final int id;
  final int tier;
  Vec2 position;
  Vec2 previous;
  final int bornTick;

  /// 0..1 scale on the radius while a merged fruit pops into being.
  double grow;

  /// Consecutive ticks spent poking above the danger line.
  int overLineTicks = 0;

  bool touched = false;

  double get fullRadius => Fruits.radii[tier];
  double get radius => fullRadius * grow;
  double get mass => fullRadius * fullRadius;
}

enum FruitEventType { drop, merge, pop, land, targetHit, gameOver }

class FruitEvent {
  const FruitEvent(this.type,
      {this.at = Vec2.zero, this.tier = 0, this.points = 0, this.combo = 0});

  final FruitEventType type;
  final Vec2 at;
  final int tier;
  final int points;
  final int combo;
}

class FruitInput {
  const FruitInput({this.aimX = 0.5, this.drop = 0});

  /// Across the jar, 0..1.
  final double aimX;
  final double drop;

  static const int channelCount = 2;

  static FruitInput fromChannels(List<double> c) =>
      FruitInput(aimX: c[0], drop: c[1]);
}

/// The watermelon game, as pure state.
///
/// A position-based solver rather than a rigid-body engine: every substep
/// moves each fruit by its implied velocity, then pushes overlapping fruits
/// apart in proportion to their size. That is stable in a tall pile — which a
/// naive impulse solver is not — and gives the soft, settling "jelly" the
/// original is loved for. It uses one square root and no trigonometry, so a
/// pile settles identically on every phone and on the verifier.
class FruitDropSimulation {
  FruitDropSimulation({required this.seed, required this.jar})
      : _rng = DeterministicRng.stream(seed, 1) {
    current = _pickTier();
    next = _pickTier();
  }

  final int seed;
  final JarSize jar;
  final DeterministicRng _rng;
  final EdgeTrigger _drop = EdgeTrigger();

  static const int tickHz = 120;
  static const double height = 900;
  static const double dangerY = 130;
  static const double holdY = 64;
  static const double gravity = 2600;

  static const int _substeps = 4;
  static const int _iterations = 2;
  static const int _cooldownTicks = 54;
  static const int _overLineLimit = tickHz * 2;
  static const int _graceTicks = tickHz;
  static const int _growTicks = 9;
  static const int _comboWindow = 60;
  static const int _maxTicks = tickHz * 60 * 20;

  double get width => jar.width;

  int tick = 0;
  int score = 0;
  int merges = 0;
  int drops = 0;
  int biggestTier = 0;
  int combo = 0;
  int _lastMergeTick = -999;
  int _nextId = 0;
  int _cooldown = 0;
  bool gameOver = false;
  RoundEnd? endReason;

  /// Points added for drops left over when the target was reached.
  int dropBonus = 0;

  /// Ticks the jar has been quiet since the round ran out of things to do.
  int _settleTicks = 0;
  static const int _settleLimit = 100;

  late int current;
  late int next;

  /// Where the held fruit hangs, 0..1 across the jar.
  double aim = 0.5;

  final List<Fruit> fruits = <Fruit>[];
  final List<FruitEvent> pendingEvents = <FruitEvent>[];

  int get dropsLeft => jar.drops - drops;

  bool get targetReached => score >= jar.target;

  bool get canDrop =>
      !gameOver && _cooldown == 0 && dropsLeft > 0 && !targetReached;
  bool get isComplete => gameOver;

  /// 0..1: how close the worst fruit is to ending the game.
  double get danger {
    var worst = 0;
    for (final f in fruits) {
      if (f.overLineTicks > worst) worst = f.overLineTicks;
    }
    return worst / _overLineLimit;
  }

  /// The held fruit's centre x.
  double get holdX {
    final r = Fruits.radii[current];
    return clampD(aim * width, r, width - r);
  }

  int _pickTier() {
    var total = 0;
    for (final w in Fruits.dropWeights) {
      total += w;
    }
    var roll = _rng.nextInt(total);
    for (var i = 0; i < Fruits.dropWeights.length; i++) {
      roll -= Fruits.dropWeights[i];
      if (roll < 0) return i;
    }
    return 0;
  }

  void step(FruitInput input) {
    pendingEvents.clear();
    if (gameOver) return;
    tick++;
    aim = clampD(input.aimX, 0, 1);
    final dropped = _drop.rising(input.drop);

    if (_cooldown > 0) _cooldown--;
    if (dropped && canDrop) _dropFruit();

    for (final f in fruits) {
      if (f.grow < 1) f.grow = clampD(f.grow + 1 / _growTicks, 0, 1);
    }

    const dt = 1 / (tickHz * _substeps);
    for (var s = 0; s < _substeps; s++) {
      _integrate(dt);
      for (var i = 0; i < _iterations; i++) {
        _solve();
      }
    }
    final mergesBefore = merges;
    final wasReached = targetReached;
    _merge();
    if (!wasReached && targetReached) {
      pendingEvents.add(FruitEvent(FruitEventType.targetHit, points: score));
    }
    _checkDanger();
    if (gameOver) return;

    // Out of fruit, or target reached: let the cascade finish, then end. A
    // merge still happening resets the wait, so a chain that tips the score
    // over the target in its last second still counts.
    if ((dropsLeft == 0 || targetReached) && _cooldown == 0) {
      _settleTicks = merges == mergesBefore ? _settleTicks + 1 : 0;
      if (_settleTicks >= _settleLimit) {
        if (targetReached) {
          dropBonus = dropsLeft * Fruits.dropBonus;
          score += dropBonus;
          _end(RoundEnd.targetHit);
        } else {
          _end(RoundEnd.outOfDrops);
        }
        return;
      }
    }

    if (tick >= _maxTicks) _end(RoundEnd.outOfDrops);
  }

  void _dropFruit() {
    final fruit = Fruit(
      id: _nextId++,
      tier: current,
      position: Vec2(holdX, holdY),
      bornTick: tick,
    );
    fruits.add(fruit);
    drops++;
    current = next;
    next = _pickTier();
    _cooldown = _cooldownTicks;
    pendingEvents.add(FruitEvent(FruitEventType.drop, at: fruit.position, tier: fruit.tier));
  }

  void _integrate(double dt) {
    final gStep = gravity * dt * dt;
    for (final f in fruits) {
      var velocity = f.position - f.previous;
      // A hard cap on per-substep travel. A merge that spawns a big fruit
      // inside a pile can otherwise fling a small one through a wall.
      // Free fall from the top of the jar peaks near 4.5 units a substep, so
      // 7 never limits a real fall and does stop a launch.
      const maxStep = 7.0;
      if (velocity.lengthSquared > maxStep * maxStep) {
        velocity = velocity.withLength(maxStep);
      }
      // Nothing in this game should ever travel *up* fast. A merge may nudge
      // its neighbours; it may not launch them. 2.2 a substep is a hop of
      // about 200 units, which reads as a bounce.
      if (velocity.y < -2.2) velocity = Vec2(velocity.x, -2.2);
      f.previous = f.position;
      f.position = f.position + velocity * 0.9992 + Vec2(0, gStep);
    }
  }

  void _solve() {
    // Sort-and-sweep on x. The list is nearly sorted from the last pass, so
    // insertion sort is close to linear.
    for (var i = 1; i < fruits.length; i++) {
      final f = fruits[i];
      var j = i - 1;
      while (j >= 0 && fruits[j].position.x > f.position.x) {
        fruits[j + 1] = fruits[j];
        j--;
      }
      fruits[j + 1] = f;
    }

    for (var i = 0; i < fruits.length; i++) {
      final a = fruits[i];
      for (var j = i + 1; j < fruits.length; j++) {
        final b = fruits[j];
        final reach = a.radius + b.radius;
        if (b.position.x - a.position.x >= reach) break;
        final delta = b.position - a.position;
        final distSq = delta.lengthSquared;
        if (distSq >= reach * reach) continue;
        final dist = delta.length;
        final normal = dist > 1e-6 ? delta / dist : const Vec2(0, 1);
        final overlap = reach - dist;
        final total = a.mass + b.mass;
        // Soft: resolve most, not all, of the overlap per iteration, and never
        // more than a few units at once. A position-based solver turns every
        // correction into velocity, so a fruit that pops into being inside a
        // pile would otherwise fire its neighbours out of the jar — it did,
        // and a fruit in orbit above the danger line ended the game at 300.
        final push = overlap * 0.8 < 3.0 ? overlap * 0.8 : 3.0;
        a.position = a.position - normal * (push * b.mass / total);
        b.position = b.position + normal * (push * a.mass / total);
        a.touched = true;
        b.touched = true;
      }
    }

    final w = width;
    for (final f in fruits) {
      final r = f.radius;
      var p = f.position;
      if (p.x < r) {
        p = Vec2(r, p.y);
        f.touched = true;
      } else if (p.x > w - r) {
        p = Vec2(w - r, p.y);
        f.touched = true;
      }
      if (p.y > height - r) {
        p = Vec2(p.x, height - r);
        // Floor friction: bleed horizontal speed by moving the previous
        // position toward the current one.
        final vx = p.x - f.previous.x;
        f.previous = Vec2(p.x - vx * 0.92, f.previous.y);
        f.touched = true;
      }
      f.position = p;
    }
  }

  void _merge() {
    // Ordered by id so which pair merges first is independent of the sort.
    final byId = List<Fruit>.of(fruits)..sort((a, b) => a.id.compareTo(b.id));
    final gone = <int>{};
    final born = <Fruit>[];
    for (var i = 0; i < byId.length; i++) {
      final a = byId[i];
      if (gone.contains(a.id)) continue;
      for (var j = i + 1; j < byId.length; j++) {
        final b = byId[j];
        if (b.tier != a.tier || gone.contains(b.id)) continue;
        final reach = a.radius + b.radius + 1.5;
        if ((b.position - a.position).lengthSquared > reach * reach) continue;

        gone
          ..add(a.id)
          ..add(b.id);
        final at = (a.position * a.mass + b.position * b.mass) / (a.mass + b.mass);
        final velocity = ((a.position - a.previous) + (b.position - b.previous)) * 0.5;

        combo = tick - _lastMergeTick <= _comboWindow ? combo + 1 : 1;
        _lastMergeTick = tick;
        merges++;

        if (a.tier == Fruits.watermelon) {
          final points = Fruits.pointsFor(Fruits.count) + Fruits.watermelonBonus;
          score += points;
          pendingEvents.add(FruitEvent(FruitEventType.pop,
              at: at, tier: a.tier, points: points, combo: combo));
        } else {
          final tier = a.tier + 1;
          final points = Fruits.pointsFor(tier);
          score += points;
          if (tier > biggestTier) biggestTier = tier;
          final fruit = Fruit(
            id: _nextId++,
            tier: tier,
            position: at,
            bornTick: tick,
            growFrom: 0.62,
          )..previous = at - velocity;
          fruit.touched = true;
          born.add(fruit);
          pendingEvents.add(FruitEvent(FruitEventType.merge,
              at: at, tier: tier, points: points, combo: combo));
        }
        break;
      }
    }
    if (gone.isEmpty) return;
    fruits
      ..removeWhere((f) => gone.contains(f.id))
      ..addAll(born);
  }

  void _checkDanger() {
    for (final f in fruits) {
      final rising = f.position.y - f.previous.y < -1.5;
      final settled = f.touched && !rising && tick - f.bornTick > _graceTicks;
      if (settled && f.position.y - f.fullRadius < dangerY) {
        f.overLineTicks++;
        if (f.overLineTicks >= _overLineLimit) {
          _end(RoundEnd.jarFull);
          return;
        }
      } else {
        f.overLineTicks = 0;
      }
    }
  }

  void _end(RoundEnd reason) {
    gameOver = true;
    endReason = reason;
    pendingEvents.add(const FruitEvent(FruitEventType.gameOver));
  }

  double get normalizedSkill => clampD(score / (jar.target * 1.5), 0, 1);

  GameResult buildResult({String? sessionToken, List<int>? replay}) => GameResult(
        gameSlug: 'fruit_drop',
        mode: GameMode.vsBot,
        botDifficulty: jar.difficulty,
        durationMs: tick * 1000 ~/ tickHz,
        p1Score: score,
        p2Score: jar.target,
        outcome: score >= jar.target ? MatchOutcome.p1Win : MatchOutcome.p2Win,
        normalizedSkill: normalizedSkill,
        seed: seed,
        tickCount: tick,
        replay: replay,
        sessionToken: sessionToken,
      );
}
