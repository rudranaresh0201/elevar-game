import 'package:game_core/game_core.dart';

import 'bot.dart';
import 'field.dart';
import 'state.dart';
import 'world.dart';

/// The soccer match, as pure state.
///
/// Advance it one tick at a time with [step]. It draws nothing, plays nothing,
/// and reads no clock — call it 120 times and one second of match has
/// happened, whether that took a second or two milliseconds. That property is
/// what lets the server replay a submitted match in a few milliseconds and
/// check the score.
///
/// ## Why the simulation owns the gesture
///
/// The touch layer reports a finger: down or up, and where. It does not report
/// "player flicked disc 3 at 80% power". Which disc was grabbed, which way it
/// will go, how hard, and whether the drag was long enough to count at all are
/// all decided here. That is deliberate — the renderer is the half of the game
/// a tampered client controls, and a rule that lives there is a rule that can
/// be rewritten. It also means the aim line drawn on screen is read back out
/// of the simulation, so what you see and what will happen cannot disagree.
class SoccerSimulation {
  SoccerSimulation({
    required this.seed,
    required this.mode,
    this.botDifficulty,
    this.rules = SoccerRules.standard,
  }) : assert(
          mode != GameMode.vsBot || botDifficulty != null,
          'A bot match needs a difficulty',
        ) {
    _kickoffRng = DeterministicRng.stream(seed, 1);

    // Who kicks off is the one thing about the opening that is not symmetric,
    // so it is drawn from the seed rather than fixed — otherwise P1 has a
    // permanent first-mover advantage and the bot's win rates are measuring
    // that as much as its skill.
    final firstTurn =
        _kickoffRng.nextUint32().isEven ? SoccerSide.p1 : SoccerSide.p2;

    state = SoccerState(world: SoccerWorld.kickoff(), turn: firstTurn)
      ..phase = SoccerPhase.kickoff
      ..freezeTicks = rules.kickoffFreezeTicks;

    if (mode == GameMode.vsBot) {
      _bot = SoccerBot(
        profile: SoccerBotProfile.of(botDifficulty!),
        side: SoccerSide.p2,
        seed: seed,
      );
    }
  }

  final int seed;
  final GameMode mode;
  final BotDifficulty? botDifficulty;
  final SoccerRules rules;

  late final SoccerState state;
  late final DeterministicRng _kickoffRng;
  SoccerBot? _bot;

  final List<SoccerEvent> _events = <SoccerEvent>[];

  /// Events raised by the most recent [step]. Valid until the next one.
  List<SoccerEvent> get pendingEvents => _events;

  int _tick = 0;
  int get tick => _tick;

  /// Held pointer state, so a tick with no fresh input behaves exactly as a
  /// thumb resting still on the glass does.
  SoccerInput _held = SoccerInput.idle;

  /// The bot's chosen shot, and how long until it takes it.
  BotShot? _botShot;
  int _botThinkLeft = 0;

  /// Distance from the ball to the goal the flicking side is attacking, as it
  /// was when the turn's flick was taken. Feeds the accuracy half of the skill
  /// score.
  double _ballGoalDistanceAtFlick = 0;
  bool _ballTouchedThisTurn = false;
  SoccerSide _flickingSide = SoccerSide.p1;

  bool get isComplete => state.phase == SoccerPhase.complete;

  /// Three channels, whatever the mode. See [SoccerInput].
  int get replayChannelCount => 3;

  /// True when the side to play is the in-simulation bot rather than a human.
  bool get botToPlay =>
      mode == GameMode.vsBot && state.turn == SoccerSide.p2;

  /// The input actually in effect this tick, after holding the last value
  /// through ticks with no new one. The replay recorder writes *these*.
  SoccerInput get heldInput => _held;

  // --- the tick ------------------------------------------------------------

  /// Advances the match by exactly one tick.
  void step(SoccerInput? input) {
    _events.clear();
    if (state.phase == SoccerPhase.complete) return;
    if (input != null) _held = input;

    switch (state.phase) {
      case SoccerPhase.kickoff:
        state.freezeTicks--;
        if (state.freezeTicks <= 0) _beginTurn();
      case SoccerPhase.aiming:
        if (botToPlay) {
          _botAimTick();
        } else {
          _humanAimTick();
        }
        // Checked after the aim, so a flick released on the very last tick
        // still counts. Losing a shot to a one-tick race is the kind of thing
        // a player correctly reads as the game cheating.
        if (state.phase == SoccerPhase.aiming) {
          state.aimTicksLeft--;
          if (state.aimTicksLeft <= 0) _endTurn(TurnEnd.timedOut);
        }
      case SoccerPhase.resolving:
        _resolveTick();
      case SoccerPhase.goalScored:
        state.freezeTicks--;
        if (state.freezeTicks <= 0) _afterGoal();
      case SoccerPhase.complete:
        break;
    }

    _tick++;
  }

  // --- turns ---------------------------------------------------------------

  void _beginTurn() {
    state
      ..phase = SoccerPhase.aiming
      ..aimTicksLeft = rules.aimTicks
      ..resolveTicks = 0
      ..aim = AimState.none;
    _botShot = null;
    _botThinkLeft = 0;
    _ballTouchedThisTurn = false;

    if (botToPlay) {
      // Chosen in one burst at the start of the pause rather than spread
      // across it: the search has to see one world, and a world that moved
      // underneath it would make the bot's own choice non-reproducible.
      _botShot = _bot!.chooseShot(state.world, state.turn);
      _botThinkLeft = rules.botThinkTicks;
      final shot = _botShot;
      if (shot != null) {
        // The bot has no finger, so its band is stretched to where a person's
        // drag would have to end to produce this shot. The renderer then draws
        // the bot lining up exactly as it draws a human doing it — you can see
        // what it is about to try, which is most of what makes losing to it
        // feel fair rather than arbitrary.
        state.aim = _aimFrom(
          shot.discIndex,
          -shot.direction * _dragLengthForPower(shot.power),
        );
      }
    }

    _emit(SoccerEventType.turnStart, _ballPosition, side: state.turn);
  }

  void _endTurn(TurnEnd how) {
    state
      ..lastTurnEnd = how
      ..turnsTaken = state.turnsTaken + 1
      ..aim = AimState.none;

    if (how == TurnEnd.timedOut) {
      _emit(SoccerEventType.turnTimeout, _ballPosition, side: state.turn);
      _passTurn();
      return;
    }

    state
      ..phase = SoccerPhase.resolving
      ..resolveTicks = 0;
  }

  /// Hands over and starts the next turn, or ends the match if the turn cap
  /// has been reached.
  void _passTurn() {
    state.turn = state.turn.other;
    if (state.turnsTaken >= rules.maxTurns) {
      _complete();
      return;
    }
    _beginTurn();
  }

  // --- aiming --------------------------------------------------------------

  void _humanAimTick() {
    if (!state.aim.isHolding) {
      // Nothing held, so the channels carry a finger position. See
      // [SoccerInput].
      if (_held.pointerDown) {
        final grabbed = _discNearest(_held.fieldPosition);
        if (grabbed != null) {
          state.aim = _aimFrom(grabbed, Vec2.zero);
          _emit(
            SoccerEventType.grab,
            state.world.bodies[grabbed].position,
            side: state.turn,
          );
        }
      }
      return;
    }

    // Holding, so the channels carry the pull vector — including on the tick
    // the finger lifts, which is what makes a release use the drag the player
    // actually ended on rather than whatever was last sampled mid-drag.
    final aim = _aimFrom(state.aim.discIndex, _held.pullVector);
    state.aim = aim;
    if (_held.pointerDown) return;

    if (aim.tooShort) {
      // A tap, or a drag too short to mean anything. Hand the disc back
      // rather than dribbling it two units and burning the turn.
      state.aim = AimState.none;
      return;
    }
    _launch(aim.discIndex, aim.direction, aim.power);
  }

  void _botAimTick() {
    _botThinkLeft--;
    if (_botThinkLeft > 0) return;
    final shot = _botShot;
    if (shot == null) {
      // No legal shot found — cannot happen with five discs on the pitch, but
      // timing out is the correct answer rather than an exception.
      _endTurn(TurnEnd.timedOut);
      return;
    }
    _launch(shot.discIndex, shot.direction, shot.power);
  }

  void _launch(int discIndex, Vec2 direction, double power) {
    _flickingSide = state.turn;
    _ballGoalDistanceAtFlick = _ballDistanceToGoal(state.turn);
    _ballTouchedThisTurn = false;

    if (state.turn == SoccerSide.p1) state.p1Flicks++;

    state.world.flick(discIndex, direction, power);
    _emit(
      SoccerEventType.flick,
      state.world.bodies[discIndex].position,
      side: state.turn,
      intensity: power,
    );
    _endTurn(TurnEnd.flicked);
  }

  /// The playable disc whose centre is nearest [pointer], within the grab
  /// radius.
  ///
  /// Nearest-centre rather than first-overlapped: with five discs a thumb can
  /// easily cover two, and picking whichever happened to be earlier in the
  /// list would make the grab feel arbitrary.
  int? _discNearest(Vec2 pointer) {
    int? best;
    var bestDistanceSquared =
        SoccerField.grabRadius * SoccerField.grabRadius;
    for (final index in state.playableDiscs) {
      final d = (state.world.bodies[index].position - pointer).lengthSquared;
      if (d <= bestDistanceSquared) {
        bestDistanceSquared = d;
        best = index;
      }
    }
    return best;
  }

  /// Builds the aim for a disc pulled back by [pull].
  ///
  /// [pull] is the drag itself — the disc leaves along its opposite, because
  /// the gesture is a slingshot. Length is clamped here as well as in
  /// [SoccerInput.pull], since the bot builds a pull directly and a rounding
  /// error on the 16-bit grid can land a hair over the limit.
  AimState _aimFrom(int discIndex, Vec2 pull) {
    final origin = state.world.bodies[discIndex].position;
    final raw = pull.length;
    final length =
        raw > SoccerField.maxDragLength ? SoccerField.maxDragLength : raw;
    final power = length <= SoccerField.minDragLength
        ? 0.0
        : clampD(
            (length - SoccerField.minDragLength) /
                (SoccerField.maxDragLength - SoccerField.minDragLength),
            0,
            1,
          );
    return AimState(
      discIndex: discIndex,
      origin: origin,
      anchor: origin + pull,
      direction: (-pull).normalized,
      power: power,
    );
  }

  static double _dragLengthForPower(double power) =>
      SoccerField.minDragLength +
      (SoccerField.maxDragLength - SoccerField.minDragLength) * power;

  // --- resolving -----------------------------------------------------------

  void _resolveTick() {
    final scorer = state.world.step(rules.stepSeconds);
    _forwardWorldEvents();
    state.resolveTicks++;

    if (scorer != null) {
      _onGoal(scorer);
      return;
    }

    if (state.world.atRest || state.resolveTicks >= rules.maxResolveTicks) {
      // The cap is a guarantee that a turn terminates, not a expectation that
      // it will be hit. A full-power flick is at rest inside 300 ticks; only a
      // ball trapped in a pocket of discs ever reaches 660.
      state.world.forceRest();
      _scoreTurnForSkill();
      _passTurn();
    }
  }

  void _forwardWorldEvents() {
    for (final event in state.world.pendingEvents) {
      switch (event.type) {
        case WorldEventType.ballHit:
          if (!_ballTouchedThisTurn) {
            _ballTouchedThisTurn = true;
            if (_flickingSide == SoccerSide.p1) state.p1BallTouches++;
          }
          _emit(
            SoccerEventType.ballHit,
            event.at,
            intensity: event.intensity,
          );
        case WorldEventType.discHit:
          _emit(
            SoccerEventType.discHit,
            event.at,
            intensity: event.intensity,
          );
        case WorldEventType.wallHit:
          _emit(
            SoccerEventType.wallHit,
            event.at,
            intensity: event.intensity,
          );
        case WorldEventType.postHit:
          _emit(
            SoccerEventType.postHit,
            event.at,
            intensity: event.intensity,
          );
      }
    }
  }

  /// Credits P1 with a flick that moved the ball toward the goal it is
  /// attacking. Called once the turn's physics has settled.
  void _scoreTurnForSkill() {
    if (_flickingSide != SoccerSide.p1) return;
    if (!_ballTouchedThisTurn) return;
    final now = _ballDistanceToGoal(SoccerSide.p1);
    // A 40-unit threshold rather than any improvement at all: a ball nudged
    // three units closer is not a progressive pass, it is noise, and counting
    // it would make the accuracy term reward poking the ball at random.
    if (now < _ballGoalDistanceAtFlick - 40) state.p1ProgressiveFlicks++;
  }

  // --- goals ---------------------------------------------------------------

  void _onGoal(SoccerSide scorer) {
    if (scorer == SoccerSide.p1) {
      state.p1Goals++;
    } else {
      state.p2Goals++;
    }
    // A goal is always progressive, however it arrived — including an own goal
    // by the opponent, which was still caused by P1's last touch often enough
    // that arguing about it costs more than it is worth.
    if (_flickingSide == SoccerSide.p1 && scorer == SoccerSide.p1) {
      state.p1ProgressiveFlicks++;
      if (!_ballTouchedThisTurn) {
        _ballTouchedThisTurn = true;
        state.p1BallTouches++;
      }
    }

    state
      ..lastScorer = scorer
      ..phase = SoccerPhase.goalScored
      ..freezeTicks = rules.goalFreezeTicks
      ..aim = AimState.none;
    _emit(SoccerEventType.goal, _ballPosition, side: scorer);
  }

  void _afterGoal() {
    if (rules.isMatchOver(state.p1Goals, state.p2Goals) ||
        state.turnsTaken >= rules.maxTurns) {
      _complete();
      return;
    }
    state.world.resetToFormation();
    // The side that conceded restarts, as football has it.
    state
      ..turn = state.lastScorer!.other
      ..phase = SoccerPhase.kickoff
      ..freezeTicks = rules.kickoffFreezeTicks;
  }

  void _complete() {
    state
      ..phase = SoccerPhase.complete
      ..aim = AimState.none;
    _emit(SoccerEventType.matchComplete, _ballPosition);
  }

  // --- results -------------------------------------------------------------

  /// Skill on the 0..1 scale every Elevar game reports, from P1's perspective.
  ///
  /// Half of it is the goal margin, which rewards winning. The rest is what
  /// the player did with their turns: how often a flick actually connected
  /// with the ball, and how often it moved the ball toward the goal they were
  /// attacking. A beginner who wins a scrappy 3-2 and a player who wins 3-0
  /// with every flick on target do not score the same, which is the point —
  /// the server's payout formula sees only this number and has to treat every
  /// game in the hub on the same terms.
  double get normalizedSkill {
    final margin = clampD(
      (state.p1Goals - state.p2Goals + rules.targetGoals) /
          (2.0 * rules.targetGoals),
      0,
      1,
    );
    final flicks = state.p1Flicks;
    final contact = flicks == 0 ? 0.0 : state.p1BallTouches / flicks;
    final progression =
        flicks == 0 ? 0.0 : state.p1ProgressiveFlicks / flicks;
    return clampD(
      0.5 * margin + 0.2 * contact + 0.3 * clampD(progression / 0.6, 0, 1),
      0,
      1,
    );
  }

  int get durationMs => (_tick * 1000) ~/ rules.tickHz;

  MatchOutcome get outcome => state.p1Goals > state.p2Goals
      ? MatchOutcome.p1Win
      : state.p2Goals > state.p1Goals
          ? MatchOutcome.p2Win
          : MatchOutcome.draw;

  /// Packages the finished match for submission to `/v1/matches`.
  GameResult buildResult({String? sessionToken, List<int>? replay}) =>
      GameResult(
        gameSlug: 'soccer',
        mode: mode,
        botDifficulty: botDifficulty,
        durationMs: durationMs,
        p1Score: state.p1Goals,
        p2Score: state.p2Goals,
        outcome: outcome,
        normalizedSkill: normalizedSkill,
        seed: seed,
        tickCount: _tick,
        replay: replay,
        sessionToken: sessionToken,
      );

  // --- helpers -------------------------------------------------------------

  Vec2 get _ballPosition => state.world.ball.position;

  double _ballDistanceToGoal(SoccerSide side) {
    final ball = state.world.ball.position;
    final goal = Vec2(SoccerField.centreX, SoccerField.attackGoalY(side));
    return (goal - ball).length;
  }

  void _emit(
    SoccerEventType type,
    Vec2 at, {
    SoccerSide? side,
    double intensity = 1,
  }) =>
      _events.add(
        SoccerEvent(type, at: at, side: side, intensity: intensity),
      );
}
