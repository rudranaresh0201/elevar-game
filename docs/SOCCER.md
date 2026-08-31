# Soccer — how it works, and what had to be measured

Game four. Same shape as the other three: a pure-Dart simulation nothing can
see, a Flame renderer that can only look, and one line in the registry.

- `packages/soccer_sim/` — rules, physics, bot. No Flutter, no Flame.
- `packages/game_soccer/` — the pitch, the counters, the slingshot band.
- `app/lib/screens/soccer_*.dart` — mode select and the host screen.

It is table soccer: five counters a side on a portrait pitch, and a turn is one
flick. First to three goals, or whoever is ahead after forty-four turns.

If you only read one section, read §3. The input encoding was rebuilt once
because a scripted player kept losing turns to a clamp rather than to the bot,
and that turned out to be a real flaw a real thumb would have hit too.

---

## 1. The format

**First to three goals, or full time at forty-four turns.** Both sides also get
a twelve-second shot clock per turn.

Three formats ship, all built from the same `SoccerRules`:

| | goals | turns | roughly |
|---|---|---|---|
| `quick` | 2 | 26 | 90s |
| `standard` (default) | 3 | 44 | 3 min |
| `cup` | 5 | 70 | 5 min |

Every one of those bounds exists for the same reason cricket's does: the
server's plausibility rules check score against elapsed time, and a format that
can run forever gives them nothing to check. Three separate things guarantee
termination — the goal target, the turn cap, and a 5.5-second cap on how long a
single turn's physics may run.

The shot clock is the one that matters for how it *feels*. A turn-based game
on a shared phone without one is a hostage situation.

---

## 2. The physics

Eleven circles in a rectangle. Ten counters and a ball.

**Substeps, not swept collisions.** Motion is integrated in four substeps of
`1/120` s and contacts are resolved after each. That is not a shortcut, it is a
bound: the furthest any body moves between overlap tests is
`speedCap / 120 / substeps` = 7.3 units, against a smallest radius of 26. Deep
tunnelling is arithmetically impossible. Raise `speedCap` without raising
`substepsPerTick` and it stops being — the constant carries that warning.

**Impulses, not repositioning.** Each pair gets a positional correction and,
if they are closing, an impulse:

```
j = -(1 + e) * (relative · n) / (invMassA + invMassB)
```

The positional correction is applied *unconditionally*, even to a pair that is
already separating. Without that, a counter resting against another sinks into
it a fraction of a unit per tick over a hundred ticks of contact.

**Restitution is per pair, not global.** Counter on counter is 0.42 — two heavy
discs clack and stop. Counter on ball is 0.88, because that is the one
collision the whole game is about. The ball is also light (`invMass` 1/0.42),
which is why a struck ball leaves faster than the counter that struck it.

**Posts are real.** Four immovable circles at the corners of the goal mouths.
Without them a ball crossing the end line one unit outside the mouth teleports
from *goal* to *goal kick* with nothing in between. With them it rattles, which
is both fairer and the best thing that happens in a match.

---

## 3. The input encoding, and why it was rebuilt

This is the section worth keeping.

A replay stores normalised `[0, 1]` field coordinates on a 16-bit grid. The
obvious encoding for a slingshot is therefore *where the finger is*, and that is
how it was built first.

It has a flaw that only shows up at the edges of the pitch, which is exactly
where it matters. A player holding the counter nearest the bottom touchline has
about 140 units of room to pull back into before the coordinate clamps at 1.0 —
so they **cannot reach full power in the one direction they most want to
shoot.** Near a corner it is worse, because clamping one axis also rotates the
aim.

It was found by measurement rather than by looking. The balance harness plays
through the real gesture, and its scripted human was losing turns to a clamp
rather than to the bot: fixing it moved the skill-1.00 win rate against `hard`
from 29% to 46% with no change to the bot at all.

The fix is to send the **pull vector** instead of the finger position:

| channel | while nothing is held | while a counter is held |
|---|---|---|
| `pointerDown` | a finger is on the glass | still holding |
| `a` | finger x | pull vector x |
| `b` | finger y | pull vector y |

The components are mapped from `[-maxDragLength, +maxDragLength]` onto `[0, 1]`,
so they still ride the existing 16-bit grid at about a hundredth of a unit. The
finger can now travel anywhere on the glass and the counter it left behind does
not care.

What the touch layer gained is only the subtraction. **Power, direction,
whether the drag was long enough to count and which counter is held are all
still decided by the simulation**, so a tampered client cannot flick harder than
the drag it reports.

### 3.1 The fast-flick race

There is a second, subtler thing here, and it has a widget test of its own.

The simulation only samples input every sixth tick. A grab is therefore
registered up to 50 ms after the finger lands. A touch layer that drops the
gesture the instant the finger lifts eats every flick taken in under 50 ms —
and those are exactly the flicks that felt best to take.

`SoccerGame` keeps a released gesture alive until the simulation has
acknowledged it, or for 24 ticks if it never does. Retiring on
`!aim.isHolding` alone looks right and is the bug.

---

## 4. The bot

It does not evaluate a position with a hand-written opinion about soccer. It
clones the world, takes each candidate flick, and **plays it out with the same
physics the match uses**, then scores where the ball ended up.

Two consequences, and both are why it is worth the cycles:

- **It plays the physics, not a model of the physics.** Rebounds off the posts,
  cannons off its own defenders and going in off an opponent are all found for
  free, because they are found by doing them. Nothing in `bot.dart` knows what
  a ricochet is.
- **It cannot drift out of sync with the game.** Retuning restitution or damping
  retunes the bot in the same commit.

Candidates are *ideas*, not angles: the "ghost ball" contact point for a shot at
the goal, the naive poke straight at the ball, two ghosts aimed at the posts,
and two lateral offsets that cut across it. All vector arithmetic — a
perpendicular is a component swap and a sign flip — so no trigonometry enters
the simulation.

Cost, measured: **1.1 ms easy, 5.3 ms medium, 16.8 ms hard** per turn, spent in
one burst inside the thinking pause the player already sees. Rollouts run at
half the match's substep count, which halves the price for a loss of fidelity
that only ever makes the bot slightly wrong about a ricochet.

### 4.1 The dial that matters most

`discsConsidered` — how many counters, nearest the ball first, the search will
look at. A bot that considers all five finds the one good shot on the pitch
every single turn. A bot that considers the two nearest plays like somebody who
has not looked at the whole board, which reads as human in a way that adding
noise to a perfect answer never does.

`aimJitter` is the other half, and it is applied **after** the shot is chosen —
so the bot takes a different shot from the one it evaluated. That is what a
missed shot actually is for a person: the plan was fine and the thumb was not.

---

## 5. The measured ladder

`dart run tool/balance.dart`, 32 matches per cell, scripted human:

| bot | skill 0.35 | 0.60 | 0.85 | 1.00 | avg goals | avg secs | avg turns |
|---|---|---|---|---|---|---|---|
| easy | 72% | 88% | 94% | 100% | 2.8 | 84 | 31 |
| medium | 31% | 56% | 88% | 97% | 3.2 | 97 | 35 |
| hard | 6% | 6% | 50% | 72% | 3.6 | 97 | 34 |

Monotonic down every column and across every row. **These come from a scripted
opponent, not from people — retune against real players before launch.** Every
dial is in `packages/soccer_sim/lib/src/bot.dart` and the table above
regenerates in about four minutes.

---

## 6. What is deliberately absent

- **A foul for missing the ball.** Some flick games pass a free turn to the
  opponent if your counter never touches the ball. It punishes exactly the
  beginner who cannot aim yet, which is the person the hub can least afford to
  lose.
- **Positional play between goals.** The formation resets after every goal.
  Playing on from where the pile-up left everyone is defensible and can hand the
  scoring side a second goal off the same lucky bounce.
- **Anything that needs a network.** Both modes are on one device. Online
  matchmaking is a different product and is not pretended at.
