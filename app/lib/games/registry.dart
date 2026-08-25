import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:game_core/game_core.dart';

import '../screens/mode_select_screen.dart';
import '../screens/racing_mode_select_screen.dart';
import 'elevar_game.dart';

/// Ping pong: two paddles, one table.
class PingPongEntry extends ElevarGame {
  const PingPongEntry();

  @override
  String get slug => 'ping_pong';

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

/// Every game the hub knows about, in the order the grid shows them.
///
/// Adding a game is a line here plus one [ElevarGame]. Nothing in the hub, the
/// result screen, the points formula or the ledger changes — which is the
/// property `docs/PLAN.md` §4 was after, now that there are two real entries to
/// check it against rather than one.
const List<ElevarGame> elevarGames = <ElevarGame>[
  CarRacingEntry(),
  PingPongEntry(),
  ComingSoonGame(
    slug: 'air_hockey',
    title: 'AIR\nHOCKEY',
    accent: ElevarColors.p2,
  ),
  ComingSoonGame(
    slug: 'reaction_duel',
    title: 'REACTION\nDUEL',
    accent: ElevarColors.ball,
  ),
];
