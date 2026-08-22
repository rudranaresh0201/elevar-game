import 'dart:math' as math;

import 'package:game_core/game_core.dart';

import 'bot.dart';
import 'field.dart';
import 'state.dart';

/// The ping pong match, as pure state.
///
/// Advance it one tick at a time with [step]. It draws nothing, plays nothing,
/// and reads no clock — call it 120 times and 1 second of match has happened,
/// whether that took 1 second or 2 milliseconds. That property is what lets the
/// server replay a submitted match in a few milliseconds and check the score.
class PingPongSimulation {
  PingPongSimulation({
    required this.seed,
    required this.mode,
    this.botDifficulty,
    this.rules = PongRules.standard,
  }) : assert(
          mode != GameMode.vsBot || botDifficulty != null,
          'A bot match needs a difficulty',
        ) {
    _serveRng = DeterministicRng.stream(seed, 1);

    final xBounds = (
      center: PongField.width / 2,
      half: (PongField.maxPaddleX() - PongField.minPaddleX()) / 2,
    );

    final p1 = PaddleState(
      position: Vec2(PongField.width / 2, PongField.p1MaxY() - 40),
      bounds: Aabb(
        Vec2(xBounds.center, (PongField.p1MinY() + PongField.p1MaxY()) / 2),
        Vec2(xBounds.half, (PongField.p1MaxY() - PongField.p1MinY()) / 2),
      ),
      maxSpeed: PongField.humanPaddleMaxSpeed,
    );

    final p2 = PaddleState(
      position: Vec2(PongField.width / 2, PongField.p2MinY() + 40),
      bounds: Aabb(
        Vec2(xBounds.center, (PongField.p2MinY() + PongField.p2MaxY()) / 2),
        Vec2(xBounds.half, (PongField.p2MaxY() - PongField.p2MinY()) / 2),
      ),
      maxSpeed: mode == GameMode.vsBot
          ? BotProfile.of(botDifficulty!).maxSpeed
          : PongField.humanPaddleMaxSpeed,
    );

    state = PongState(
      ball: BallState(
        position: const Vec2(PongField.width / 2, PongField.netY),
        velocity: Vec2.zero,
      ),
      p1: p1,
      p2: p2,
      phase: PongPhase.serving,
    )
      ..freezeTicks = rules.serveFreezeTicks
      ..serveToward = _serveRng.nextUint32().isEven ? PongSide.p1 : PongSide.p2;

    if (mode == GameMode.vsBot) {
      _bot = PongBot(
        profile: BotProfile.of(botDifficulty!),
        side: PongSide.p2,
        seed: seed,
        tickHz: rules.tickHz,
      );
    }

    _p1Target = _normalise(p1.position);
    _p2Target = _normalise(p2.position);
  }

  final int seed;
  final GameMode mode;
  final BotDifficulty? botDifficulty;
  final PongRules rules;

  late final PongState state;
  late final DeterministicRng _serveRng;
  PongBot? _bot;

  final List<PongEvent> _events = <PongEvent>[];

  /// Events raised by the most recent [step]. Valid until the next one.
  List<PongEvent> get pendingEvents => _events;

  int _tick = 0;
  int get tick => _tick;

  late Vec2 _p1Target;
  late Vec2 _p2Target;

  /// Ticks before each paddle may register another contact.
  ///
  /// Without this a paddle can strike the same ball on consecutive ticks —
  /// nudging clear of the surface is not enough when the paddle itself is
  /// travelling at 3600 units/second and simply catches up with the ball again.
  /// The symptom is not a visible glitch but a corrupted rally count, which
  /// feeds the skill score and the stalemate breaker.
  int _p1ContactCooldown = 0;
  int _p2ContactCooldown = 0;

  /// Roughly 50 ms. At any legal ball speed the ball is hundreds of units clear
  /// by the time this expires, so no genuine contact is ever suppressed.
  static const int _contactCooldownTicks = 6;

  /// The normalised target actually in effect this tick, after holding the last
  /// value through ticks with no new input. The replay recorder writes *these*,
  /// not the raw input, so a replay feeds back exactly what the live match saw.
  Vec2 get p1Target => _p1Target;
  Vec2 get p2Target => _p2Target;

  bool get isComplete => state.phase == PongPhase.complete;

  /// Number of input channels a replay of this match must carry: the human
  /// paddle only against a bot, both paddles for two humans.
  int get replayChannelCount => mode == GameMode.vsBot ? 2 : 4;

  /// Advances the match by exactly one tick.
  void step(PongInput input) {
    _events.clear();
    if (state.phase == PongPhase.complete) return;

    final dt = rules.stepSeconds;

    if (input.p1 != null) _p1Target = input.p1!;
    if (mode == GameMode.vsBot) {
      _p2Target = _bot!.update(state);
    } else if (input.p2 != null) {
      _p2Target = input.p2!;
    }

    if (_p1ContactCooldown > 0) _p1ContactCooldown--;
    if (_p2ContactCooldown > 0) _p2ContactCooldown--;

    _movePaddle(state.p1, _p1Target, dt);
    _movePaddle(state.p2, _p2Target, dt);

    switch (state.phase) {
      case PongPhase.serving:
        state.ball.previousPosition = state.ball.position;
        state.freezeTicks--;
        if (state.freezeTicks <= 0) {
          _launchBall();
          state.phase = PongPhase.rally;
          _emit(PongEventType.serve, state.ball.position);
        }
      case PongPhase.rally:
        _integrateBall(dt);
      case PongPhase.pointScored:
        state.ball.previousPosition = state.ball.position;
        state.freezeTicks--;
        if (state.freezeTicks <= 0) {
          if (rules.isMatchOver(state.p1Score, state.p2Score)) {
            state.phase = PongPhase.complete;
            _emit(PongEventType.matchComplete, state.ball.position);
          } else {
            _resetForServe();
            state.phase = PongPhase.serving;
            state.freezeTicks = rules.serveFreezeTicks;
          }
        }
      case PongPhase.complete:
        break;
    }

    _tick++;
  }

  // --- paddles -------------------------------------------------------------

  void _movePaddle(PaddleState paddle, Vec2 normalisedTarget, double dt) {
    final target = Vec2(
      clampD(
        normalisedTarget.x * PongField.width,
        paddle.bounds.left,
        paddle.bounds.right,
      ),
      clampD(
        normalisedTarget.y * PongField.height,
        paddle.bounds.top,
        paddle.bounds.bottom,
      ),
    );

    final delta = target - paddle.position;
    final maxStep = paddle.maxSpeed * dt;

    final next = delta.lengthSquared <= maxStep * maxStep
        ? target
        : paddle.position + delta.withLength(maxStep);

    paddle.previousPosition = paddle.position;
    paddle.velocity = (next - paddle.position) / dt;
    paddle.position = next;
  }

  // --- ball ----------------------------------------------------------------

  void _launchBall() {
    // Serve towards whoever just conceded. Direction is built from components,
    // never from an angle, so no trigonometry enters the simulation.
    final towardP1 = state.serveToward == PongSide.p1;
    final spread = _serveRng.nextRange(-0.75, 0.75);
    final direction = Vec2(spread, towardP1 ? 1.0 : -1.0).normalized;

    state.ball
      ..velocity = direction * PongField.ballInitialSpeed
      ..previousPosition = state.ball.position;
    state.rallyHits = 0;
  }

  /// Shrinks both paddles once a rally has run past the stalemate threshold.
  void _applyStalematePressure() {
    final scale = rules.paddleScaleForRally(state.rallyHits);
    state.p1.scale = scale;
    state.p2.scale = scale;
  }

  void _resetForServe() {
    _p1ContactCooldown = 0;
    _p2ContactCooldown = 0;
    state.p1.scale = 1;
    state.p2.scale = 1;
    state.ball
      ..position = const Vec2(PongField.width / 2, PongField.netY)
      ..previousPosition = const Vec2(PongField.width / 2, PongField.netY)
      ..velocity = Vec2.zero;
    state.rallyHits = 0;
  }

  /// Moves the ball through one tick, resolving contacts in time order.
  ///
  /// The loop advances to the *first* contact, responds, then continues with
  /// the leftover motion — rather than moving the whole step and asking what
  /// overlaps afterwards. At 2300 units/second a ball covers 19 units per tick
  /// against a 48-unit-thick paddle, so a naive check would survive today and
  /// break the moment anyone raises the speed cap or lowers the tick rate.
  void _integrateBall(double dt) {
    var position = state.ball.position;
    var velocity = state.ball.velocity;
    state.ball.previousPosition = position;

    var remaining = 1.0;
    for (var iteration = 0; iteration < 4 && remaining > 1e-6; iteration++) {
      final delta = velocity * (dt * remaining);

      SweepHit? earliest;
      PaddleState? struck;
      PongSide? struckSide;

      for (final candidate in <(PaddleState, PongSide)>[
        (state.p1, PongSide.p1),
        (state.p2, PongSide.p2),
      ]) {
        final cooling = candidate.$2 == PongSide.p1
            ? _p1ContactCooldown > 0
            : _p2ContactCooldown > 0;
        if (cooling) continue;

        final hit = sweepCircleAgainstAabb(
          position,
          delta,
          candidate.$1.body,
          PongField.ballRadius,
        );
        if (hit != null && (earliest == null || hit.t < earliest.t)) {
          earliest = hit;
          struck = candidate.$1;
          struckSide = candidate.$2;
        }
      }

      if (earliest == null) {
        position += delta;
        remaining = 0;
      } else {
        position += delta * earliest.t;
        velocity = _bounceOffPaddle(
          velocity,
          position,
          struck!,
          struckSide!,
          earliest.normal,
        );
        // Nudge clear of the surface so the next sweep does not immediately
        // re-detect the contact it just resolved.
        position += earliest.normal * 2.0;
        remaining *= 1.0 - earliest.t;

        if (struckSide == PongSide.p1) {
          _p1ContactCooldown = _contactCooldownTicks;
        } else {
          _p2ContactCooldown = _contactCooldownTicks;
        }

        state.rallyHits++;
        state.totalRallyHits++;
        if (state.rallyHits > state.longestRally) {
          state.longestRally = state.rallyHits;
        }
        _applyStalematePressure();
        _emit(
          PongEventType.paddleHit,
          position,
          side: struckSide,
          intensity: clampD(velocity.length / PongField.ballMaxSpeed, 0, 1),
        );
      }

      // Side walls. A half-plane reflection is exact and cheaper than a sweep,
      // and the walls never move.
      if (position.x < PongField.ballRadius) {
        position = Vec2(PongField.ballRadius, position.y);
        velocity = Vec2(velocity.x.abs(), velocity.y);
        _emit(PongEventType.wallHit, position);
      } else if (position.x > PongField.width - PongField.ballRadius) {
        position = Vec2(PongField.width - PongField.ballRadius, position.y);
        velocity = Vec2(-velocity.x.abs(), velocity.y);
        _emit(PongEventType.wallHit, position);
      }
    }

    state.ball
      ..position = position
      ..velocity = velocity;

    if (position.y < -PongField.ballRadius) {
      _awardPoint(PongSide.p1);
    } else if (position.y > PongField.height + PongField.ballRadius) {
      _awardPoint(PongSide.p2);
    }
  }

  Vec2 _bounceOffPaddle(
    Vec2 velocity,
    Vec2 contact,
    PaddleState paddle,
    PongSide side,
    Vec2 normal,
  ) {
    // A "front" hit is one on the face the paddle is supposed to defend with.
    // Clipping the paddle's edge or back — which happens when the ball is
    // already past it — reflects plainly, with no return direction and no speed
    // bonus. Forcing every contact to return the ball would let a beaten player
    // recover a point they had lost.
    final isFrontHit = side == PongSide.p1 ? normal.y < -0.5 : normal.y > 0.5;
    if (!isFrontHit) return velocity.reflect(normal);

    final offset = clampD(
      (contact.x - paddle.position.x) / paddle.currentHalfWidth,
      -1,
      1,
    );
    final towardOpponent = side == PongSide.p1 ? -1.0 : 1.0;

    final lateral = offset * PongField.hitOffsetInfluence +
        paddle.velocity.x * PongField.paddleVelocityInfluence;

    var direction = Vec2(lateral, towardOpponent).normalized;

    // Keep the return from flattening out into an endless cross-court rally.
    if (direction.y.abs() < PongField.minVerticalDirection) {
      const minY = PongField.minVerticalDirection;
      final lateralSign = direction.x < 0 ? -1.0 : 1.0;
      direction = Vec2(
        lateralSign * math.sqrt(1 - minY * minY),
        towardOpponent * minY,
      );
    }

    final speed = math.min(
      velocity.length * PongField.ballSpeedGain,
      PongField.ballMaxSpeed,
    );
    return direction * speed;
  }

  void _awardPoint(PongSide scorer) {
    if (scorer == PongSide.p1) {
      state.p1Score++;
    } else {
      state.p2Score++;
    }
    state.pointsPlayed++;
    state.phase = PongPhase.pointScored;
    state.freezeTicks = rules.pointFreezeTicks;
    // The player who conceded receives the next serve.
    state.serveToward = scorer == PongSide.p1 ? PongSide.p2 : PongSide.p1;
    _emit(PongEventType.point, state.ball.position, side: scorer);
  }

  // --- results -------------------------------------------------------------

  /// Skill on the 0..1 scale every Elevar game reports, from P1's perspective.
  ///
  /// Half of it is rally length, which rewards sustained play, and half is
  /// score margin, which rewards winning. A player who scrapes a win through
  /// long rallies and one who wins comfortably in short ones score similarly —
  /// which is the point, since the server's payout formula sees only this
  /// number and must treat every game in the hub on the same terms.
  double get normalizedSkill {
    final rallyComponent = clampD(state.averageRally / 8.0, 0, 1);
    final marginComponent = clampD(
      (state.p1Score - state.p2Score + rules.targetScore) /
          (2.0 * rules.targetScore),
      0,
      1,
    );
    return clampD(0.5 * rallyComponent + 0.5 * marginComponent, 0, 1);
  }

  int get durationMs => (_tick * 1000) ~/ rules.tickHz;

  /// Packages the finished match for submission to `/v1/matches`.
  GameResult buildResult({String? sessionToken, List<int>? replay}) {
    final outcome = state.p1Score > state.p2Score
        ? MatchOutcome.p1Win
        : state.p2Score > state.p1Score
            ? MatchOutcome.p2Win
            : MatchOutcome.draw;

    return GameResult(
      gameSlug: 'ping_pong',
      mode: mode,
      botDifficulty: botDifficulty,
      durationMs: durationMs,
      p1Score: state.p1Score,
      p2Score: state.p2Score,
      outcome: outcome,
      normalizedSkill: normalizedSkill,
      seed: seed,
      tickCount: _tick,
      replay: replay,
      sessionToken: sessionToken,
    );
  }

  // --- helpers -------------------------------------------------------------

  Vec2 _normalise(Vec2 fieldPosition) => Vec2(
        fieldPosition.x / PongField.width,
        fieldPosition.y / PongField.height,
      );

  void _emit(
    PongEventType type,
    Vec2 at, {
    PongSide? side,
    double intensity = 1,
  }) =>
      _events.add(PongEvent(type, at: at, side: side, intensity: intensity));
}
