/// Car racing, rendered.
///
/// Everything here is presentation: drawing, touch, dust, haptics. The rules
/// live in `racing_sim` and this package cannot change them — it feeds input in
/// and paints what comes out. Deleting this package would leave a still-
/// playable, still-verifiable game with nothing to look at.
library;

export 'src/controls.dart';
export 'src/game_config.dart';
export 'src/race_scene.dart';
export 'src/race_view.dart';
export 'src/racing_game.dart';
