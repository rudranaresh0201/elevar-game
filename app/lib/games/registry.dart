import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:game_archery/game_archery.dart';
import 'package:game_core/game_core.dart';
import 'package:game_fruitdrop/game_fruitdrop.dart';
import 'package:game_penalty/game_penalty.dart';
import 'package:game_wallcricket/game_wallcricket.dart';

import '../screens/cricket_mode_select_screen.dart';
import '../screens/fruit_drop_screens.dart';
import '../screens/mode_select_screen.dart';
import '../screens/racing_mode_select_screen.dart';
import '../screens/shooting_screens.dart';
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

/// Cricket: a bat you hold, a bowling machine, and walls worth runs.
///
/// Single-player, like Top Spinner: there is no bowler to control, only a
/// target to beat. That is why [supportedModes] is a set rather than a flag.
class CricketEntry extends ElevarGame {
  const CricketEntry();

  @override
  String get slug => 'cricket';

  @override
  IconData get glyph => Icons.sports_cricket_rounded;

  @override
  String get title => 'CRICKET';

  @override
  String get tagline => 'Swing the bat. Smash the walls. Beat the target.';

  @override
  Color get accent => WallCricketColors.shirt;

  @override
  Set<GameMode> get supportedModes => const <GameMode>{GameMode.vsBot};

  @override
  Widget buildModeSelect(BuildContext context) =>
      const CricketModeSelectScreen();
}

/// Football: a penalty shootout. Swipe to shoot, tap to dive.
///
/// Replaced table soccer, which played like carrom. The slug is `football`
/// rather than `soccer` because it is a different game, and its stats should
/// not be read as a continuation of the old one's.
class SoccerEntry extends ElevarGame {
  const SoccerEntry();

  @override
  String get slug => 'football';

  @override
  IconData get glyph => Icons.sports_soccer_rounded;

  @override
  String get title => 'PENALTY\nSHOOTOUT';

  @override
  String get tagline => 'Five kicks each. Bend it past the keeper.';

  @override
  Color get accent => PenaltyColors.turf;

  @override
  Set<GameMode> get supportedModes =>
      const <GameMode>{GameMode.local2P, GameMode.vsBot};

  @override
  Widget buildModeSelect(BuildContext context) =>
      const SoccerModeSelectScreen();
}

/// Shooting: a turn-based archery duel over a hill, in the wind.
class ShootingEntry extends ElevarGame {
  const ShootingEntry();

  @override
  String get slug => 'shooting';

  @override
  IconData get glyph => Icons.gps_fixed_rounded;

  @override
  String get title => 'SHOOTING';

  @override
  String get tagline => 'Drag, aim, loose. Mind the wind.';

  @override
  Color get accent => DuelColors.p2;

  @override
  Set<GameMode> get supportedModes =>
      const <GameMode>{GameMode.local2P, GameMode.vsBot};

  @override
  Widget buildModeSelect(BuildContext context) =>
      const ShootingModeSelectScreen();
}

/// Fruit Drop: the watermelon game.
class FruitDropEntry extends ElevarGame {
  const FruitDropEntry();

  @override
  String get slug => 'fruit_drop';

  @override
  IconData get glyph => Icons.apple_rounded;

  @override
  String get title => 'FRUIT\nDROP';

  @override
  String get tagline => 'Drop, merge, grow a watermelon.';

  @override
  Color get accent => FruitDropColors.accent;

  @override
  Set<GameMode> get supportedModes => const <GameMode>{GameMode.vsBot};

  @override
  Widget buildModeSelect(BuildContext context) =>
      const FruitDropModeSelectScreen();
}

/// Every game the hub knows about, in the order the grid shows them. The
/// first is the featured tile, so the newest game goes first.
///
/// Adding a game is a line here plus one [ElevarGame]. Nothing in the hub, the
/// result screen, the points formula or the ledger changes — which is the
/// property `docs/PLAN.md` §4 was after.
const List<ElevarGame> elevarGames = <ElevarGame>[
  FruitDropEntry(),
  ShootingEntry(),
  SoccerEntry(),
  CricketEntry(),
  CarRacingEntry(),
  PingPongEntry(),
];
