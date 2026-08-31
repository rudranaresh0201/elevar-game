import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart';
import 'package:game_cricket/game_cricket.dart';

import '../screens/cricket_mode_select_screen.dart';
import '../screens/mode_select_screen.dart';
import '../screens/racing_mode_select_screen.dart';
import '../screens/soccer_mode_select_screen.dart';
import 'elevar_game.dart';

/// Ping pong: two paddles, one table.
class PingPongEntry extends ElevarGame {
  const PingPongEntry();

  @override
  String get slug => 'ping_pong';

  @override
  IconData get glyph => Icons.sports_tennis_rounded;

  @override
  String get title => 'PING\nPONG';

  @override
  String get tagline => 'Pass the phone, or take on the machine.';

  @override
  Color get accent => ElevarColors.table;

  @override
  Set<GameMode> get supportedModes =>
      const <GameMode>{GameMode.local2P, GameMode.vsBot};

  @override
  Widget buildModeSelect(BuildContext context) => const ModeSelectScreen();
}

/// Car racing: two cars, one circuit.
class CarRacingEntry extends ElevarGame {
  const CarRacingEntry();

  @override
  String get slug => 'car_racing';

  @override
  IconData get glyph => Icons.sports_score_rounded;

  @override
  String get title => 'CAR\nRACING';

  @override
  String get tagline => 'Three laps. Two thumbs each. No mercy.';

  @override
  Color get accent => RacingColors.carP1;

  @override
  Set<GameMode> get supportedModes =>
      const <GameMode>{GameMode.local2P, GameMode.vsBot};

  @override
  Widget buildModeSelect(BuildContext context) =>
      const RacingModeSelectScreen();
}

/// Cricket: two overs, one thumb.
///
/// The only single-mode entry, and the reason [supportedModes] is a set rather
/// than a flag. Cricket is asymmetric — somebody bats and somebody bowls — so
/// pass-the-phone would mean handing the device over between every ball.
class CricketEntry extends ElevarGame {
  const CricketEntry();

  @override
  String get slug => 'cricket';

  @override
  IconData get glyph => Icons.sports_cricket_rounded;

  @override
  String get title => 'CRICKET';

  @override
  String get tagline => 'Two overs. Bat first, then defend it.';

  @override
  Color get accent => CricketColors.batterShirt;

  @override
  Set<GameMode> get supportedModes => const <GameMode>{GameMode.vsBot};

  @override
  Widget buildModeSelect(BuildContext context) =>
      const CricketModeSelectScreen();
}

/// Soccer: ten counters, one ball, one flick a turn.
///
/// The second entry to offer both shared-device modes, and the first turn-based
/// one. Nothing in the hub, the ledger or the payout formula learned that a
/// turn exists — a match still reduces to a [GameResult] and the payout still
/// reads only `normalizedSkill`. That is the plugin contract earning its keep
/// for the second time.
class SoccerEntry extends ElevarGame {
  const SoccerEntry();

  @override
  String get slug => 'soccer';

  @override
  IconData get glyph => Icons.sports_soccer_rounded;

  @override
  String get title => 'SOCCER';

  @override
  String get tagline => 'Ten counters, one ball. Flick and pass it on.';

  @override
  Color get accent => SoccerColors.turf;

  @override
  Set<GameMode> get supportedModes =>
      const <GameMode>{GameMode.local2P, GameMode.vsBot};

  @override
  Widget buildModeSelect(BuildContext context) =>
      const SoccerModeSelectScreen();
}

/// Every game the hub knows about, in the order the grid shows them.
///
/// Adding a game is a line here plus one [ElevarGame]. Nothing in the hub, the
/// result screen, the points formula or the ledger changes — which is the
/// property `docs/PLAN.md` §4 was after. Cricket is the proof: it is a
/// wholly different shape of game and it cost this file one line.
const List<ElevarGame> elevarGames = <ElevarGame>[
  SoccerEntry(),
  CricketEntry(),
  CarRacingEntry(),
  PingPongEntry(),
  ComingSoonGame(
    slug: 'shooting',
    title: 'SHOOTING',
    accent: ElevarColors.p2,
  ),
  ComingSoonGame(
    slug: 'fruit_drop',
    title: 'FRUIT\nDROP',
    accent: ElevarColors.ball,
  ),
];
