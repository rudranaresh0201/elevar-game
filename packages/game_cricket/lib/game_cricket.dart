/// Cricket, rendered.
///
/// Everything here is presentation: drawing, touch, sparks, haptics. The rules
/// live in `cricket_sim` and this package cannot change them — it feeds input
/// in and paints what comes out. Deleting this package would leave a still
/// playable, still verifiable game with nothing to look at.
///
/// The two ideas worth knowing before reading it:
///
/// * **One gesture per ball.** Batting folds direction, power and timing into a
///   single drag-and-release; bowling is a single touch on a plan view of the
///   pitch. Three separate controls for one shot turns every ball into an admin
///   task, which is the opposite of what this hub is for.
/// * **The timing ring exists because timing is invisible.** A player who
///   mistimes three balls and cannot tell whether they were early or late has
///   been given nothing to improve on.
library;

export 'src/controls.dart';
export 'src/cricket_game.dart';
export 'src/cricket_scene.dart';
export 'src/cricket_view.dart';
export 'src/game_config.dart';
