/// Cricket, as pure state.
///
/// Two overs a side, three wickets, bat first and then defend. Nothing here
/// imports Flutter, Flame or `dart:ui`: the same code runs inside the app and,
/// unchanged, inside a headless server worker that re-simulates a submitted
/// match to check the score it was sent.
///
/// It obeys `game_core`'s determinism contract — fixed timestep, no
/// transcendental maths, no ambient randomness. The two places that would
/// normally reach for trigonometry are the boundary and the fielding, and
/// neither does: the rope is an ellipse tested in its squared form, and
/// fielders chase along normalised vectors. Field placements are literal
/// coordinates rather than angles around a circle, for the same reason the
/// racing circuits are.
///
/// ## The shape of a ball
///
/// ```
/// runUp ──▶ delivery ──▶ ballInPlay ──▶ betweenBalls ──┐
///   ▲                        │                          │
///   └──────────────────────────────────────────────────┘
/// ```
///
/// A swing is registered during `delivery` and resolved the tick the ball
/// reaches the contact line. Timing decides most of the outcome and playing
/// with the line decides the rest; a mishit turns the bat in the hand and puts
/// the ball up, which is what makes a top edge a catch rather than a boundary.
library;

export 'src/bot.dart';
export 'src/field.dart';
export 'src/ground.dart';
export 'src/replay_harness.dart';
export 'src/simulation.dart';
export 'src/state.dart';
