# Car Racing — build notes

**Status:** built and playable · two circuits · vs bot and two-on-one-phone
**Packages:** `racing_sim` (pure Dart) · `game_racing` (Flame renderer + controls)

This is the second game in the hub, and the first one to test whether the
architecture in [`PLAN.md`](PLAN.md) actually holds. It does, with two things
the plan had not anticipated — both recorded below, because both were found by
measuring rather than by reasoning.

---

## 1. Shape of the game

Top-down, whole circuit on screen, no camera scrolling. That choice does a lot
of work: both cars are always visible, which is what makes a shared-screen race
readable, and it means the renderer reuses ping pong's letterbox approach
unchanged rather than growing a camera system.

- **Field:** a fixed 1000 × 1500 simulation space, letterboxed onto the device.
  A race plays identically on a cheap phone and a tablet — a correctness
  requirement, not a nicety, since two devices must agree on the finishing order
  for a replay to verify anything.
- **Race:** 2, 3 or 5 laps. First car home wins; the loser gets 12 seconds to
  finish before the flag drops.
- **Modes:** `vsBot` (easy / medium / hard) and `local2P`.
- **Score:** laps completed. That keeps the wire format identical to ping pong's
  and lets the server's plausibility rules apply to racing without learning what
  a lap is.

---

## 2. Controls

Each driver gets a band across their end of the screen: a **left/right rocker**
at one side, **BRAKE** and **GAS** at the other. P2's band is rotated 180°, the
same convention the ping pong score pill uses.

**The bands are reserved first and the circuit is letterboxed into what is
left.** The obvious alternative — fit the track to the screen and overlay the
controls on its corners — puts fingers on the racing line exactly when the
racing gets close.

Two details that are not cosmetic:

- The buttons are raw `Listener`s, **not** `GestureDetector`s. Two people on one
  phone put up to eight thumbs on the glass, and the gesture arena exists to
  decide which *single* recogniser wins a pointer — precisely the wrong
  behaviour when four simultaneous presses are four independent facts. There is
  a test that holds four at once and asserts both cars accelerate.
- Button sizes are computed from the available width. Fixed pixel sizes came to
  402pt against the 358pt a 390pt phone offers, and overflowed the row on the
  most common screen there is. Caught by a widget test, not by looking at it.

An **auto-gas** toggle holds the throttle for you, leaving steering and braking.
Accessibility, and genuinely nicer for anyone who finds four targets a thumb too
many.

---

## 3. Determinism, where racing differs from ping pong

`game_core`'s contract bans transcendental maths and ambient randomness. Ping
pong obeys that almost for free — a ball's direction is a vector and bounces are
reflections. A car has a *heading that rotates*, which is where `sin` and `cos`
normally enter a codebase. Two answers:

### Rotation without an angle

```dart
static Vec2 _rotate(Vec2 v, double k) =>
    Vec2(v.x - v.y * k, v.y + v.x * k).normalized;
```

Multiplying by the complex number `(1, k)` rotates by `atan(k)` and scales by
`sqrt(1 + k²)`; normalising removes the scale. No angle is ever formed. `sqrt`
is safe because IEEE-754 requires it to be correctly rounded, so the same code
gives the same bits on a phone and on the server.

The circuits are literal coordinates smoothed by a Catmull-Rom spline for the
same reason. A track generated with `sin`/`cos` would be built *slightly*
differently by the server's libm, and every replay it verified would be checked
against a circuit fractionally the wrong shape.

The bot obeys this too — it derives corner radius from curvature using
`θ ≈ 2√bend` rather than an arc-cosine.

### Input quantisation, again — but discretely

Ping pong learned that the live match must consume input at the replay's
precision, not just record it there. Racing has the same problem with a sharper
edge: steering is *ternary*, and `0.5` does not survive a 16-bit round trip as
`0.5` — it comes back as `0.50000762…`. Fed in as a steering value, a car
holding "straight" curves a fraction of a degree per lap, and a simulation
compounds that until the replay and the race disagree about who won.

`CarInput.fromChannels` therefore snaps the decoded value back onto exactly the
three states a button can produce. The live path goes through the same snap.
There is a test that round-trips all twelve possible inputs.

Replays sample at **30 Hz** rather than ping pong's 20. A dragged paddle is a
smooth signal that survives coarse sampling; a button press is an edge, and at
20 Hz a stab at the brake could sit 50 ms behind the thumb. It costs almost
nothing — a held button delta-encodes to one zero byte per channel — and a full
two-player race records in well under 40 KB before gzip.

---

## 4. The track model

One idea does five jobs. A circuit is a closed centreline plus a half-width, and
every question the race needs answered comes from **projecting a position onto
that centreline**:

| Question | Answer |
|---|---|
| Am I on the dirt? | perpendicular distance ≤ `halfWidth` |
| How far round am I? | arc length from the start line |
| Which way is forward? | the segment's unit direction |
| Who is winning? | compare unwrapped arc length |
| Where should the bot aim? | the centreline a lookahead further on |

The renderer then **strokes that same centreline** at `halfWidth * 2` with round
caps and joins — which is exactly the set of points the surface test calls
"on track". The picture and the physics cannot drift apart, because they are the
same definition.

Lap counting unwraps the projection: each tick's raw distance is folded into a
signed step (`shortestDelta`) and accumulated. Driving backwards *decreases* the
total, so reversing over the line can never award a lap — there is a test.

### The anti-cut claim, corrected

The projection search is windowed around last tick's segment. My first pass
documented that as the anti-cut rule. **It isn't, and the test that asserted it
failed.** A car creeping across the infield still advances its projection
segment by segment; the window only stops the projection *jumping* between two
parts of the circuit that pass close together.

What actually stops corner cutting is grass drag, and it is worth having the
numbers (`tool/cutcheck.dart` re-derives them from the constants):

| | |
|---|---|
| Terminal speed on dirt | 331 units/s |
| Terminal speed on grass | 80 units/s |
| Momentum carried onto grass | ~74 units, then it bogs down |
| Shortcut across DUSTBOWL's middle | 1,138 units ≈ **14.2 s** |
| The same trip round the circuit | 1,660 units ≈ **8.1 s** |

Cutting is a loss on the clock. That is a far better deterrent than a rule
telling a player their lap did not count, and it needs no rule at all. A
per-tick cap on banked progress remains, as cheap insurance against projection
pathologies.

---

## 5. The grip limit — and the difficulty cliff it fixed

The first playable build had no limit on cornering force: a car could take any
corner at any speed. Everything worked, every test passed, and the balance table
looked like this:

```
| bot    | skill 0.35 | skill 0.60 | skill 0.85 | skill 1.00 | clean |
| easy   |       100% |       100% |       100% |       100% |  100% |
| medium |         3% |         3% |       100% |       100% |  100% |
| hard   |         0% |         0% |         0% |       100% |  100% |
```

Every cell is 0% or 100%. Nobody ever left the track. With no grip limit,
braking is pointless, so every driver simply drove flat out and **the faster top
speed won every single race** — the ladder had collapsed into a comparison of
one number.

The fix is one constant. A tyre can only pull so much sideways, so the most yaw
it can support is `gripLimit / speed`; ask for more and the car understeers wide
instead of turning:

```dart
final maxYaw = RaceField.lateralGripLimit / speed;
if (yawRate > maxYaw) yawRate = maxYaw;
```

That single line is what makes a racing line exist, makes the brake pedal worth
a thumb, and turns the bot's caution dial into something a player can feel. With
it — plus compressing the pace gaps, because 3-10 s a lap of difference swamps
±1 s of variance — the ladder became:

```
=== DUSTBOWL (3 laps) ===
| bot    | skill 0.35 | skill 0.60 | skill 0.85 | skill 1.00 | avg lap | avg secs |
|--------|------------|------------|------------|------------|---------|----------|
| easy   |       100% |       100% |       100% |       100% |    15.6 |       56 |
| medium |        20% |        40% |        93% |        98% |    15.5 |       50 |
| hard   |         5% |        15% |       100% |       100% |    15.5 |       50 |

=== SUNSET LOOP (3 laps) ===
| easy   |       100% |       100% |       100% |       100% |    13.5 |       49 |
| medium |        20% |        68% |       100% |       100% |    13.4 |       44 |
| hard   |         0% |        10% |       100% |       100% |    13.4 |       45 |
```

Hard reads as a step rather than a slope above skill 0.6, and that is a property
of the car rather than of the dials. Solo lap times are easy 17.8 s, medium
16.1 s, hard 15.4 s, against a proxy player spanning 16.2 s at skill 0.35 down
to 15.1 s at skill 1.0 — the whole performance envelope of this car on this
circuit is about two and a half seconds wide. Past skill 0.6 the proxy is quick
enough to beat everything, so the gap between 93% and 100% is sampling noise
rather than a statement about the bots. The monotonicity test is therefore
measured at 0.6, where the ladder still discriminates cleanly.

Easy is beatable by anyone, medium is a genuine fight in the middle of the
range, and hard goes to a strong player around half the time on the wide
circuit and a third on the tight one. Regenerate with
`dart run tool/balance.dart`.

**These come from a scripted opponent, not people. Retune against real players
before launch** — the dials are all in `packages/racing_sim/lib/src/bot.dart`,
and `tool/diagnose.dart` shows the solo pace each difficulty actually runs.

---

## 6. The bot

Seven dials, one algorithm. Every difficulty runs the same driver, so "hard"
cannot contain a bug that "easy" doesn't.

| Dial | Easy | Medium | Hard |
|---|---|---|---|
| Reaction delay | 280 ms | 170 ms | 60 ms |
| Pace (of terminal) | 0.90 | 0.93 | 1.00 |
| Corner caution | 1.10 | 1.09 | 1.00 |
| Line wander | ±62 | ±34 | ±6 units |
| Corner-entry mistakes | 11% | 7% | 2.5% |
| Lookahead | 130 | 150 | 195 units |
| Solo lap, Dustbowl | 17.8 s | 16.1 s | 15.4 s |

`cornerCaution` turns out to be a poor dial to express a range on, and it is
worth knowing why before reaching for it again. It multiplies the corner speed
the bot asks for, and `lateralGripLimit` is a hard ceiling on what it can
actually get. A hair above 1.0 costs real time; anything below 1.0 buys nothing,
because the clamp binds first. Dropping hard from 0.92 to 0.85 moved its lap by
0.27 s and then stopped mattering at all. Reaction, lookahead and line noise are
linear, and are where a real spread lives.

Caution above 1 lifts earlier than necessary and loses time; below 1 asks for
more than the tyres have and runs wide. A mistake is a missed braking point,
long enough to actually put a wheel on the grass — at 46 ticks it was invisible,
and the whole ladder collapsed because mistakes cost nothing.

The bot is held to the same three steering values a thumb can produce, so it can
never make an input a human could not. It also unsticks itself: a car wedged on
the tyre wall reverses out, because a bot stuck against scenery would otherwise
turn a race into a five-minute wait.

---

## 7. Tests

```bash
cd packages/racing_sim  && dart test      # 42
cd packages/game_racing && flutter test   # 14
```

The ones that matter:

- **`simulation_test.dart`** — the load-bearing file. Given a seed and an input
  log, the race reproduces bit-identically; a recorded race re-runs to its own
  result; a forged score does not survive; a truncated replay is rejected.
  **If this goes red, no racing score the server receives can be verified.**
- **`track_test.dart`** — projection, lap counting, and the honest version of
  the anti-cut claim: that cutting costs more time than it saves.
- **`balance_test.dart`** — the ladder is monotonic, every race terminates on
  both circuits at every difficulty, and mistakes still cost time on the grass.
  That last one is the tripwire for the cliff coming back.
- **`race_view_test.dart`** — plays through the real widget with real thumbs on
  real buttons, including four at once, then verifies the replay it produced.
- **`golden_test.dart`** — renders real frames to `test/goldens/*.png`. Less an
  assertion suite than a way to *look* at the game without a phone; the
  circuit's proportions and the control bands were checked against the
  reference art this way, and it is how the start line was caught sitting on a
  curve at an angle. Platform-specific — see `docs/SETUP.md`.

---

## 8. Making it playable

The first build on a real phone came back with one sentence: *it is really tough
to play, and if you go off you cannot get back on.* Both halves were true, and
the second was a genuine trap rather than a difficulty.

`tool/stuck.dart` reproduces the original bug. Drive deliberately into the
scenery, then hold full throttle with the wheel hard over — what any player
does — and after six seconds the car is doing **0.6 units/s and travelling
backwards.** Three things were interlocking:

1. **Grass was a tar pit.** `dragOnGrass` of 3.30 put terminal speed off the
   circuit at 80 units/s against 331 on the dirt.
2. **The fence reflected instead of releasing.** `_constrainToField` subtracted
   1.35x the outward velocity, pushing the car back inwards while its nose
   still pointed out — so the throttle drove it straight into the fence again.
3. **Steering authority is proportional to speed, and speed was zero.** With
   the fence holding the car at a standstill, the wheel did nothing. That is a
   deadlock, and no amount of player skill escapes it.

Each fix alone leaves one of the other two able to trap a car, so all three
changed together:

| | was | now |
|---|---|---|
| `dragOnGrass` | 3.30 | 2.30 |
| `gripOnGrass` | 2.6 | 3.6 |
| `lateralGripLimitGrass` | 95 | 170 |
| `lateralGripLimit` | 270 | 330 |
| Dustbowl half-width | 105 | 132 |
| Sunset Loop half-width | 122 | 150 |
| Fence | reflects at 1.35x | cancels outward, slides along |
| Steering floor | none | 0.5, **only on throttle or brake** |

The steering floor is gated deliberately. A parked car with a thumb only on the
rocker still cannot pirouette — that rule was worth keeping and has a test — but
a driver *asking* for drive can always point the car somewhere.

Widening the circuits put five trees and rocks inside the racing surface. They
were pushed back out along the centreline normal; three had nowhere left to go
inside the field and became decorations, which are painted but never collided
with.

### The marshals

Physics alone still leaves the case where a player gives up on a corner and the
car ends up stationary in a hedge. Off the circuit and under
`rescueSpeedThreshold` for two seconds, the car is lifted back onto the racing
line facing forwards at `rescueLaunchSpeed`.

It is dropped at **its own projected distance**, never a fixed respawn point, so
a recovery can never hand out progress — there is a test for exactly that,
because a safety net that advances you is an exploit. The HUD says
`RECOVERING IN 2` before it happens rather than after, so being moved reads as
help arriving instead of the screen glitching.

Corner cutting is still a loss: `tool/cutcheck.dart` measures the Dustbowl
shortcut at ~10.0 s against ~8.1 s round. The margin narrowed from 6.1 s to
1.9 s, which is the price of a forgiving surface and is still the right side of
the line.

### Auto-gas is now the default

It shipped as an accessibility option and it is simply the better game. Holding
the throttle is not a decision — nobody chooses to go slower down a straight —
and four targets for two thumbs is a lot while also reading a circuit. Turned
off, it gives back a manual throttle for anyone who wants one.

Turning it on exposed a bug worth recording. `DriverControls` reported input
**on change**, so with nothing pressed the callback never fired, the simulation
held `CarInput.coasting`, and the throttle that was supposed to be held for you
never was — auto-gas did nothing at all until you pressed some other button. It
now publishes its resting state once on mount.

### The start hint

The lights go out, the car sits still, and nothing on screen says why. That is
indistinguishable from the game having hung, and it is what the first phone test
actually reported. A `HOLD GAS` banner now appears beside the pedal for the
first four seconds of green-flag running and dismisses itself the moment the car
is moving, so it is there for the player who does not yet know and never for the
one who does.

Its dismissal needed care. The HUD only rebuilds when `hudRevision` changes, so
bumping the notifier *while* a banner is up leaves the last frame containing it
painted on screen forever. The banner has to be told to leave, not merely stop
being told to stay.

---

## 9. What is not done

- **No audio.** There is a seam for it in `RacingGame._reactTo`, and no assets.
- **Two circuits.** The track model is data-driven, so a third is a list of
  coordinates in `tracks.dart`.
- **No server.** Races bank into the local ledger and queue in the outbox; see
  `app/lib/data/points_repository.dart`.
- **Bot dials are calibrated against a script, not people.** See §5.
