import 'package:game_core/game_core.dart';

import 'field.dart';

/// What a body is. The ball is the only one of its kind, and the only one that
/// may pass through a goal mouth.
enum BodyKind { disc, ball }

/// A circle with mass, and the only kind of thing the physics knows about.
///
/// Fields are mutable and owned by [SoccerWorld]; treat them as read-only from
/// outside it.
class SoccerBody {
  SoccerBody({
    required this.position,
    required this.radius,
    required this.invMass,
    required this.kind,
    required this.damping,
    this.team,
  })  : previousPosition = position,
        velocity = Vec2.zero;

  Vec2 position;

  /// Position at the end of the previous tick, so the renderer can interpolate
  /// between simulation steps rather than snapping to them.
  Vec2 previousPosition;

  Vec2 velocity;

  final double radius;
  final double invMass;
  final BodyKind kind;
  final double damping;

  /// Null for the ball.
  final SoccerSide? team;

  bool get isBall => kind == BodyKind.ball;

  double get speed => velocity.length;

  bool get moving => velocity.lengthSquared > 0;

  SoccerBody _copy() => SoccerBody(
        position: position,
        radius: radius,
        invMass: invMass,
        kind: kind,
        damping: damping,
        team: team,
      )
        ..previousPosition = previousPosition
        ..velocity = velocity;
}

/// Something worth reacting to, produced by a physics step.
///
/// The world never plays a sound or shakes a screen — it says what happened
/// and lets the renderer decide. That separation is what keeps the simulation
/// runnable headlessly on a server.
class WorldEvent {
  const WorldEvent(this.type, {required this.at, this.intensity = 1});

  final WorldEventType type;
  final Vec2 at;

  /// 0..1 — how hard, for scaling shake, particles and pitch.
  final double intensity;
}

enum WorldEventType { discHit, ballHit, wallHit, postHit }

/// The eleven circles and the rectangle they live in.
///
/// Kept separate from the match state for one concrete reason: the bot
/// evaluates a candidate flick by [clone]ing this and rolling it forward, so
/// the physics has to be runnable with no match, no turn, and no rules
/// attached to it. That constraint is also what keeps the collision code
/// honest — it cannot reach for anything it does not own.
class SoccerWorld {
  SoccerWorld._(this.bodies);

  /// Builds the kickoff formation. [firstTouch] is the side taking the
  /// kickoff, whose centre-forward starts a little closer to the spot.
  factory SoccerWorld.kickoff() {
    final bodies = <SoccerBody>[];
    for (final side in SoccerSide.values) {
      for (final slot in SoccerField.p1Formation) {
        final y = side == SoccerSide.p1
            ? slot.$2
            : SoccerField.mirrorY(slot.$2);
        final x = side == SoccerSide.p1
            ? slot.$1
            // Mirroring x as well as y keeps the two formations point
            // symmetric rather than merely reflected, which is what a real
            // table has: rotate the board 180 degrees and it is unchanged.
            : SoccerField.width - slot.$1;
        bodies.add(
          SoccerBody(
            position: Vec2(x, y),
            radius: SoccerField.discRadius,
            invMass: SoccerField.discInvMass,
            kind: BodyKind.disc,
            damping: SoccerField.discDamping,
            team: side,
          ),
        );
      }
    }
    bodies.add(
      SoccerBody(
        position: const Vec2(SoccerField.centreX, SoccerField.centreSpotY),
        radius: SoccerField.ballRadius,
        invMass: SoccerField.ballInvMass,
        kind: BodyKind.ball,
        damping: SoccerField.ballDamping,
      ),
    );
    return SoccerWorld._(bodies);
  }

  /// P1's five discs, then P2's five, then the ball. The order is part of the
  /// replay contract — a disc is identified by its index and nothing else.
  final List<SoccerBody> bodies;

  static const int ballIndex = SoccerField.discsPerSide * 2;

  SoccerBody get ball => bodies[ballIndex];

  /// The five discs belonging to [side], by index into [bodies].
  static int firstDiscIndex(SoccerSide side) =>
      side == SoccerSide.p1 ? 0 : SoccerField.discsPerSide;

  static bool indexBelongsTo(int index, SoccerSide side) {
    final first = firstDiscIndex(side);
    return index >= first && index < first + SoccerField.discsPerSide;
  }

  final List<WorldEvent> _events = <WorldEvent>[];

  /// Events raised by the most recent [step]. Valid until the next one.
  List<WorldEvent> get pendingEvents => _events;

  /// True when nothing is moving and the turn can end.
  bool get atRest {
    for (final body in bodies) {
      if (body.moving) return false;
    }
    return true;
  }

  /// A deep copy, for the bot to roll forward and throw away.
  SoccerWorld clone() =>
      SoccerWorld._(<SoccerBody>[for (final b in bodies) b._copy()]);

  /// Sends the disc at [index] off at [direction] (need not be unit length)
  /// with [power] in `[0, 1]`.
  void flick(int index, Vec2 direction, double power) {
    final unit = direction.normalized;
    if (unit == Vec2.zero) return;
    final p = clampD(power, 0, 1);
    final speed = SoccerField.minFlickSpeed +
        (SoccerField.maxFlickSpeed - SoccerField.minFlickSpeed) * p;
    bodies[index].velocity = unit * speed;
  }

  /// Advances one simulation tick.
  ///
  /// Returns the side that scored, or null. A goal parks the ball in the net
  /// and stops the world — nothing after a goal affects the match, and letting
  /// the discs carry on rolling behind the celebration only risks a second
  /// goal being detected in the same turn.
  ///
  /// Motion is integrated in [SoccerField.substepsPerTick] equal substeps and
  /// contacts are resolved after each. That is the whole anti-tunnelling story
  /// and it is a bound, not a hope: see [SoccerField.speedCap].
  ///
  /// [substeps] defaults to the match's [SoccerField.substepsPerTick] and is
  /// lowered only by the bot's rollouts, where halving the fidelity halves the
  /// search cost and the worst case is a bot that mispredicts a ricochet —
  /// which is a bot with a flaw, not a match with a bug.
  SoccerSide? step(
    double stepSeconds, {
    bool emitEvents = true,
    int substeps = SoccerField.substepsPerTick,
  }) {
    if (emitEvents) _events.clear();
    for (final body in bodies) {
      body.previousPosition = body.position;
    }

    final dt = stepSeconds / substeps;
    for (var s = 0; s < substeps; s++) {
      for (final body in bodies) {
        if (!body.moving) continue;
        body.position += body.velocity * dt;
      }
      _resolveContacts(emitEvents);
      final scorer = _resolveBoundary(emitEvents);
      if (scorer != null) {
        _freezeEverything();
        return scorer;
      }
    }

    // Damping is applied once per tick, not once per substep, so the substep
    // count is free to change without retuning how far a flick travels.
    for (final body in bodies) {
      if (!body.moving) continue;
      var v = body.velocity * body.damping;
      if (v.lengthSquared < SoccerField.restSpeed * SoccerField.restSpeed) {
        v = Vec2.zero;
      } else if (v.lengthSquared >
          SoccerField.speedCap * SoccerField.speedCap) {
        v = v.withLength(SoccerField.speedCap);
      }
      body.velocity = v;
    }
    return null;
  }

  void _freezeEverything() {
    for (final body in bodies) {
      body.velocity = Vec2.zero;
    }
  }

  /// Stops every body dead. Used when a turn runs past its resolve cap.
  void forceRest() => _freezeEverything();

  /// Puts every disc back on its formation spot and the ball on the centre
  /// spot, with nothing moving.
  ///
  /// A restart resets positions rather than playing on from where the goal
  /// left everyone. Both are defensible; resetting is the one that cannot
  /// hand the scoring side a second goal off the same lucky pile-up.
  void resetToFormation() {
    var index = 0;
    for (final side in SoccerSide.values) {
      for (final slot in SoccerField.p1Formation) {
        final position = side == SoccerSide.p1
            ? Vec2(slot.$1, slot.$2)
            : Vec2(SoccerField.width - slot.$1, SoccerField.mirrorY(slot.$2));
        bodies[index]
          ..position = position
          ..previousPosition = position
          ..velocity = Vec2.zero;
        index++;
      }
    }
    const spot = Vec2(SoccerField.centreX, SoccerField.centreSpotY);
    ball
      ..position = spot
      ..previousPosition = spot
      ..velocity = Vec2.zero;
    _events.clear();
  }

  // --- contacts ------------------------------------------------------------

  /// Every pair, resolved as an impulse plus a positional correction.
  ///
  /// Eleven bodies is 55 pairs, which is small enough that a broad phase would
  /// cost more than it saved — and a spatial hash is one more thing that has
  /// to be bit-identical on two architectures for replay verification to hold.
  void _resolveContacts(bool emitEvents) {
    for (var i = 0; i < bodies.length; i++) {
      for (var j = i + 1; j < bodies.length; j++) {
        _resolvePair(bodies[i], bodies[j], emitEvents);
      }
    }
  }

  void _resolvePair(SoccerBody a, SoccerBody b, bool emitEvents) {
    final delta = b.position - a.position;
    final contact = a.radius + b.radius;
    final distanceSquared = delta.lengthSquared;
    if (distanceSquared >= contact * contact) return;

    // Two bodies exactly on top of each other have no contact normal to speak
    // of. Push them apart along a fixed axis rather than dividing by zero;
    // this only happens if a formation ever places two discs identically.
    final normal = distanceSquared == 0
        ? const Vec2(0, 1)
        : delta.normalized;
    final distance = distanceSquared == 0 ? 0.0 : delta.length;

    final relative = b.velocity - a.velocity;
    final separating = relative.dot(normal);

    // Positional correction first, unconditionally. A pair that is overlapping
    // but already separating still has to be pushed apart, or a disc resting
    // against another slowly sinks into it over a hundred ticks of contact.
    final overlap = contact - distance;
    if (overlap > 0) {
      final totalInvMass = a.invMass + b.invMass;
      final correction = normal * (overlap / totalInvMass);
      a.position -= correction * a.invMass;
      b.position += correction * b.invMass;
    }

    if (separating >= 0) return;

    final restitution = a.isBall || b.isBall
        ? SoccerField.discBallRestitution
        : SoccerField.discDiscRestitution;

    final impulse =
        -(1 + restitution) * separating / (a.invMass + b.invMass);
    a.velocity -= normal * (impulse * a.invMass);
    b.velocity += normal * (impulse * b.invMass);

    if (!emitEvents) return;
    final at = a.position + normal * a.radius;
    final intensity = clampD(-separating / SoccerField.maxFlickSpeed, 0, 1);
    _events.add(
      WorldEvent(
        a.isBall || b.isBall ? WorldEventType.ballHit : WorldEventType.discHit,
        at: at,
        intensity: intensity,
      ),
    );
  }

  // --- the pitch edge ------------------------------------------------------

  /// Walls, posts and goal mouths. Returns the scoring side, or null.
  SoccerSide? _resolveBoundary(bool emitEvents) {
    SoccerSide? scorer;
    for (final body in bodies) {
      final inMouth = body.isBall &&
          (body.position.x - SoccerField.centreX).abs() <
              SoccerField.goalHalfWidth;

      // Touchlines. Always solid, for everything.
      final restitution = body.isBall
          ? SoccerField.ballWallRestitution
          : SoccerField.discWallRestitution;

      if (body.position.x < SoccerField.left + body.radius) {
        body.position = Vec2(SoccerField.left + body.radius, body.position.y);
        if (body.velocity.x < 0) {
          body.velocity =
              Vec2(-body.velocity.x * restitution, body.velocity.y);
          if (emitEvents) _emitWall(body);
        }
      } else if (body.position.x > SoccerField.right - body.radius) {
        body.position = Vec2(SoccerField.right - body.radius, body.position.y);
        if (body.velocity.x > 0) {
          body.velocity =
              Vec2(-body.velocity.x * restitution, body.velocity.y);
          if (emitEvents) _emitWall(body);
        }
      }

      // The posts are resolved before the end line, so a ball clipping the
      // inside of a post is deflected rather than being teleported back onto
      // the line first and losing the deflection.
      if (body.isBall) {
        _resolvePosts(body, emitEvents);
      }

      // End lines, with a hole in each for the ball.
      if (inMouth) {
        if (body.position.y < SoccerField.topGoalLine) {
          scorer ??= SoccerSide.p1;
          _parkInNet(body, SoccerSide.p1);
        } else if (body.position.y > SoccerField.bottomGoalLine) {
          scorer ??= SoccerSide.p2;
          _parkInNet(body, SoccerSide.p2);
        }
        continue;
      }

      if (body.position.y < SoccerField.topGoalLine + body.radius) {
        body.position =
            Vec2(body.position.x, SoccerField.topGoalLine + body.radius);
        if (body.velocity.y < 0) {
          body.velocity =
              Vec2(body.velocity.x, -body.velocity.y * restitution);
          if (emitEvents) _emitWall(body);
        }
      } else if (body.position.y >
          SoccerField.bottomGoalLine - body.radius) {
        body.position =
            Vec2(body.position.x, SoccerField.bottomGoalLine - body.radius);
        if (body.velocity.y > 0) {
          body.velocity =
              Vec2(body.velocity.x, -body.velocity.y * restitution);
          if (emitEvents) _emitWall(body);
        }
      }
    }
    return scorer;
  }

  /// The four posts, as immovable circles.
  void _resolvePosts(SoccerBody ball, bool emitEvents) {
    for (final post in postPositions) {
      final delta = ball.position - post;
      final contact = ball.radius + SoccerField.postRadius;
      if (delta.lengthSquared >= contact * contact) continue;
      if (delta.lengthSquared == 0) continue;

      final normal = delta.normalized;
      ball.position = post + normal * contact;
      final into = ball.velocity.dot(normal);
      if (into < 0) {
        ball.velocity =
            ball.velocity - normal * (into * (1 + SoccerField.postRestitution));
        if (emitEvents) {
          _events.add(
            WorldEvent(
              WorldEventType.postHit,
              at: post,
              intensity: clampD(
                -into / SoccerField.maxFlickSpeed,
                0,
                1,
              ),
            ),
          );
        }
      }
    }
  }

  /// Where the ball comes to rest once it is over the line: in the net, and
  /// not one unit past the goal line, so the celebration has something to
  /// look at.
  void _parkInNet(SoccerBody ball, SoccerSide scorer) {
    final netY = scorer == SoccerSide.p1
        ? SoccerField.topGoalLine - SoccerField.goalDepth * 0.55
        : SoccerField.bottomGoalLine + SoccerField.goalDepth * 0.55;
    ball
      ..position = Vec2(
        clampD(
          ball.position.x,
          SoccerField.centreX - SoccerField.goalHalfWidth + ball.radius,
          SoccerField.centreX + SoccerField.goalHalfWidth - ball.radius,
        ),
        netY,
      )
      ..velocity = Vec2.zero;
  }

  void _emitWall(SoccerBody body) => _events.add(
        WorldEvent(
          WorldEventType.wallHit,
          at: body.position,
          intensity: clampD(body.speed / SoccerField.maxFlickSpeed, 0, 1),
        ),
      );

  /// The four post centres, as the renderer and the physics both see them.
  static const List<Vec2> postPositions = <Vec2>[
    Vec2(SoccerField.centreX - SoccerField.goalHalfWidth,
        SoccerField.topGoalLine),
    Vec2(SoccerField.centreX + SoccerField.goalHalfWidth,
        SoccerField.topGoalLine),
    Vec2(SoccerField.centreX - SoccerField.goalHalfWidth,
        SoccerField.bottomGoalLine),
    Vec2(SoccerField.centreX + SoccerField.goalHalfWidth,
        SoccerField.bottomGoalLine),
  ];
}
