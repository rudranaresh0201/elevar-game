/// The soccer simulation, with no rendering in it.
///
/// This package imports `game_core` and nothing else — no Flutter, no Flame.
/// It is the half of the game that the server can run: given a match seed and
/// the recorded human input, [SoccerSimulation] reproduces the exact final
/// score the player saw. If it doesn't, the submission was tampered with.
///
/// The game is table soccer: five discs a side on a portrait pitch, and a turn
/// is one slingshot flick. Everything about how that turn resolves — which
/// disc was grabbed, which way it goes, how hard, whether the drag was even
/// long enough to count — is decided here rather than in the touch layer, for
/// the reason given on [SoccerSimulation].
library;

export 'src/bot.dart';
export 'src/field.dart';
export 'src/replay_harness.dart';
export 'src/simulation.dart';
export 'src/state.dart';
export 'src/world.dart';
