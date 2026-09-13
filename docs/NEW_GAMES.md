# The 2026-09-13 rebuild: four games

Cricket and soccer were rebuilt, and shooting and fruit drop were added. All
four follow the same split as the rest of the hub: a pure-Dart simulation
(fixed 120 Hz ticks, `DeterministicRng`, no trig, replay-verifiable), a Flame
renderer that only looks, and one line in `app/lib/games/registry.dart`.

A new `game_core` primitive, `SampledInput`, carries **discrete actions** — a
shot, a dive, a drop — through the replay: a `pulse` holds a channel at 1 for
exactly one sample, and the simulation fires on the rising edge via
`EdgeTrigger`. Live play and the verifier see the same edge on the same tick.

## What the research said, and what was built from it

| Reference | What makes it work | What we built |
|---|---|---|
| Top Spinner Cricket (Bennett Foddy, 2008) | The mouse *is* the bat; runs come from numbered walls; out when bowled | `wallcricket`: the bat points at your finger, contact physics adds the blade's velocity to the ball, walls score 1/2/4/6, a hot zone pays ×2 each over |
| Flick Kick / Penalty Shooters | Swipe speed = power, swipe angle = direction, curved swipe = bend; keeper has a reaction delay; alternate shooter/keeper | `penalty`: swipe to shoot (aim, power, curve read from the path), tap to dive; bot keeper reacts after a delay and sometimes reads the shot; bot shooter punishes an early dive |
| Bowmasters / the snowball reference | Drag to aim with a force/angle readout and a partial arc; physics you solve by feel | `archery`: drag back to aim, first stretch of the arc shown, wind per turn, headshots, a bot that solves the shot and tightens its error each turn |
| Suika / the fruit reference | Soft "jelly" physics, merge on touch, only the five smallest fruits dropped, triangular scoring, game over above the line | `fruitdrop`: position-based circle solver with substeps, 11 tiers, triangular points, two-second danger line |
| Vlambeer, *The Art of Screenshake* | Hit-stop, shake, flash, particles, permanence | Hit-stop on clean cricket strikes, shake/flash/particles everywhere, stuck arrows stay in the hill, net bulge and crowd bob on goals |

## Things the numbers caught

Each sim has a `tool/` script that plays scripted players against it. They
found real problems, not tuning trivia:

- **Cricket:** a bat resting at guard covered the stumps — nobody touching the
  screen scored 50 on hard and was never out. The rest pose is now raised.
  The handle collided with balls passing the batter's hip; only the blade
  collides now. The pivot was too high to reach a ball at the stumps' base.
- **Penalties:** a scripted keeper saved 98% of bot shots. Keeper reach and
  human dive speed came down, bot shots got faster.
- **Fruit drop:** a merge inside a pile launched neighbours out of the jar at
  1,800 units/s; one orbiting above the danger line ended the game at 300
  points. Corrections are now capped per pair and upward speed is clamped.
- **Layout:** a smoke test at 320×640 caught the cricket over-dots row and the
  result screen's score pills overflowing (fruit drop scores are four digits),
  and rendered screenshots showed every HUD panel stretching the full screen
  height.

## Current ladders (scripted players, not people — retune before launch)

```
cricket   easy skill 0.4 win 88% · medium 0.7 win 78% · hard 1.0 win 53%
penalty   medium skill 0.6: scores 66%, saves 76% · hard: scores 50%
archery   easy 0.6 win 77% · medium 0.6 win 43% · hard 0.9 win 53%
fruitdrop targets 1000 / 2000 / 3000; the scripted dropper beats them easily
```

Run them: `dart run tool/diagnose.dart` (cricket) or `dart run tool/balance.dart`.

## Seeing it without a phone

`app/test/screenshots_test.dart` plays each game and writes PNG frames:

```
set ELEVAR_SHOTS=C:\some\folder
flutter test test/screenshots_test.dart --update-goldens
```

## Not done yet

- **Sound.** No audio in any game yet; the crack of a bat and a goal roar are
  the biggest remaining feel upgrade.
- **Fruit drop personal best** is not stored; the result screen shows the score.
- Bot tuning against real players, for all four.
