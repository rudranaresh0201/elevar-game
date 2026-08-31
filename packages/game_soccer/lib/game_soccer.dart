/// Table soccer, rendered.
///
/// Everything here is presentation: drawing, touch, particles, haptics. The
/// rules live in `soccer_sim` and this package cannot change them — it feeds
/// input in and paints what comes out. Deleting this package would leave a
/// still-playable, still-verifiable game with nothing to look at.
library;

export 'src/game_config.dart';
export 'src/soccer_game.dart';
export 'src/soccer_scene.dart';
export 'src/soccer_view.dart';
