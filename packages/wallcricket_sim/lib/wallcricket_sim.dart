/// Top Spinner-style wall cricket, as pure state.
///
/// A bowling machine, a batter, a bat you hold with your finger, and a room
/// whose walls are the scoreboard. No Flutter, no Flame: the same code runs in
/// the app and in the headless verifier, under `game_core`'s determinism
/// contract.
library;

export 'src/arena.dart';
export 'src/runner.dart';
export 'src/simulation.dart';
