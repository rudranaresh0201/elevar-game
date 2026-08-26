# Cricket — how it works, and what had to be measured

Game three. Same shape as the other two: a pure-Dart simulation nothing can see,
a Flame renderer that can only look, and one line in the registry.

- `packages/cricket_sim/` — rules, physics, fielding, bot. No Flutter, no Flame.
- `packages/game_cricket/` — the ground, the pads, the sparks.
- `app/lib/screens/cricket_*.dart` — mode select and the host screen.

If you only read one section, read §5. Five separate things in this game came
out **backwards** and every one of them was found by running numbers, not by
reading code.

---

## 1. The format, and why it isn't "until you get out"

**Two overs — 12 balls — or three wickets, whichever comes first. You bat, then
you bowl to defend.**

The obvious design is *bat until you're out*. It was rejected for two reasons,
both structural rather than aesthetic:

1. **No upper bound on duration.** The server's plausibility rules (`PLAN.md`
   §11) check score against elapsed time. A format that can run for four seconds
   or four minutes gives it nothing to check. Every innings here terminates:
   12 balls, 3 wickets, or a 240-second hard cap.
2. **One bad ball ends the session.** A first-timer who nicks off on ball one
   has played cricket for eight seconds. That is the fastest possible way to
   lose somebody on an ecommerce site who was only ever half-interested.

Three formats ship, all built from the same `CricketRules`:

| | overs | wickets | roughly |
|---|---|---|---|
| `superOver` | 1 | 2 | 40s a side |
| `powerplay` (default) | 2 | 3 | 60s a side |
| `chase` | 4 | 5 | 2min a side |

The second innings is a chase with a real target on the scoreboard, which is
what makes the bowling half a game rather than a cooldown.

---

## 2. The camera, and why the first version was dead

The simulation stores a flat 1000 × 1500 field seen from directly above, and
the first renderer drew exactly that. Every number was right and the result was
unplayable to look at: the batter was a six-pixel dot, the bowler was another
dot, the ball never grew as it arrived, and the whole thing read as a radar
display. The first person to open it said so in about four seconds.

`PitchCamera` fixed it without the simulation changing at all. It is a pinhole
projection sitting between the state and the canvas:

```
  d       = how far in front of the eye a point is
  screenX = centreX + lateral * focal / d
  screenY = horizon + (lift - height * rise) / d
```

Everything worth having falls out of those two lines. The pitch becomes a
trapezoid, wide at your feet and narrow at the far end. The mown stripes bunch
towards the horizon. Fielders in the deep are small. And the one that actually
matters for playing it: **the ball more than doubles in size coming down the
pitch**, which turns timing from a guess into something you can see arriving.

Three things about it are not obvious:

**The eye sits 154 units behind the striker, and that number is load-bearing.**
Anything nearer than `minDepth` is culled, so 154 puts the keeper (y 1012),
slip (1000) and fine leg (1180) *behind the camera*. An earlier version stood
further back and the first thing on screen was the wicketkeeper's back filling
a third of it.

**There are two cameras.** Batting looks one way down the pitch; bowling looks
the other. Watching from behind the batter you are bowling *to* would send your
own delivery away from you. It is one sign flip, and `role` changing at the
innings break rebuilds the camera.

**The vertical is stretched.** An honest camera would set `rise == focal`, but
an honest camera that also fits the ground onto a phone has to sit almost on
the deck, and from there you cannot read length at all. Every cricket game
cheats this. 1.6× is where a six looks like a six and still lands in frame.

A small top-down map stays in the corner. The perspective view hides the one
thing a batter needs in order to *aim* — where the gaps are — and without it
the swipe direction is a shrug rather than a decision.

---

## 3. Geometry

The simulation runs in the same 1000 × 1500 space the other games use, flat and
seen from above. Nothing here is in pixels, and nothing here knows the camera in
§2 exists.

```
CricketField.groundCentreX  500      groundRadiusX  468
CricketField.groundCentreY  720      groundRadiusY  590
bowlerCreaseY  520     strikerCreaseY  920     strikerY  946
contactY       904     pitchHalfWidth   46     stumpsHalfWidth  15
```

The boundary is an **ellipse**, tested in squared form so there is no `sqrt` and
no angle anywhere near it:

```dart
final dx = (p.x - groundCentreX) / groundRadiusX;
final dy = (p.y - groundCentreY) / groundRadiusY;
return dx * dx + dy * dy >= 1;
```

That ellipse was wrong the first time. The striker stood at 62% of the ground's
height, which put the square boundary roughly **three times closer than the
straight one** — every mishit off the toe went for six and every good straight
drive was caught at long-on. The current numbers put it at about 1.9:1, which is
what a real ground looks like and, more to the point, means where you aim
matters without the answer always being "square".

---

## 4. One gesture per ball

Batting is **drag and release**. The direction of the drag is where the ball
goes, its length is how hard, and the moment of release is the timing. A plain
tap is a zero-length drag, which falls out as a straight push at medium power —
the correct beginner shot, and nobody has to be told.

The alternative — a direction stick, a power slider and a swing button — is
three targets for one thumb and turns every ball into an admin task. Ping pong's
paddle is one finger; this had to be one finger too.

Bowling is a single touch on a plan view of the pitch: line across, length down,
plus four delivery chips. Same idea, and it means the half of the match you
*bowl* is something you do rather than watch.

### The timing bar

On by default, and it exists because **timing is invisible**. A new player who
mistimes three balls in a row and cannot tell whether they were early or late
has been given nothing to improve on. The bar shows the arriving ball against a
green sweet spot; the shot resolves from the same numbers, so the bar is not a
hint, it is the actual state.

It sits *above* the control band. The first version sat in the middle of the
screen, directly on top of the batter — which no assertion caught and the golden
PNG showed in a second.

---

## 5. Five things that came out backwards

Each of these passed a plausible reading of the code and was only caught by
printing a table.

**5.1 — Runs were counted from elapsed time.** A well-struck ball reaches a
fielder *sooner*, so it scored **fewer** runs than a mishit. Every difficulty
ladder was therefore inverted. Runs now come from the distance the ball is
stopped at (`unitsPerRun = 200`), which is both correct and the thing a player
already expects.

**5.2 — Almost nothing could earn a run.** `tool/_probe.dart` measured the
median live ball at 87 ticks against a 168-tick threshold: **1%** of balls
scored. Fixed by 5.1, plus slower fielders.

**5.3 — A late swing was impossible.** Contact resolved on exactly
`idealContactTick`, so a swing one tick later hit nothing. The ball's position,
velocity and height are now frozen at the moment of the swing and resolved at
`ideal + contactWindowTicks` — which is what makes early and late *different*
rather than one being "no shot at all".

**5.4 — Catches ate the game.** 4.8 to 5.3 wickets out of 6. Catching is now
gated on the ball descending, scaled by how fast it is travelling, and the
fielder pursues the *predicted landing point* (positive root of the quadratic)
rather than the ball's current position. Reach and radius both came down.

**5.5 — The measuring instrument was broken.** `tool/diagnose.dart` passed no
bowler input, so the bot faced an identical delivery every single ball. Half the
table was measuring nothing at all. Worth stating plainly: **check the
instrument before you believe the reading.**

---

## 6. The ladder

`dart run tool/diagnose.dart`, 60 matches per cell, scripted human proxy:

| bot | skill 0.3 | 0.6 | 0.9 | secs | 4s | 6s |
|---|---|---|---|---|---|---|
| easy | 38% | 75% | 98% | 50–64 | 3–5% | 4–7% |
| medium | 38% | 63% | 78% | 46–66 | 3–6% | 4–9% |
| hard | 30% | 30% | 45% | 44–66 | 3–8% | 4–10% |

Monotonic down every column and across every row, which is the property
`test/balance_test.dart` asserts. A skilled player beats easy nearly always and
hard slightly under half the time; a beginner wins about a third of the time
against anything, which is deliberate — losing every match in the first two
minutes is not a funnel.

**Roughly one ball in eight is a boundary at high skill.** That number was
tuned *up* on purpose. This is a game on a shoe shop's app, played by someone who
did not come for cricket; the fours and sixes are the reason they play a second
match.

As with ping pong and racing, these come from a scripted proxy, not people.
**Retune against real players before launch** — every dial is in
`packages/cricket_sim/lib/src/bot.dart`.

---

## 7. The replay bug worth remembering

The recorder samples input every 4 ticks. A swing is a **one-tick edge**. So a
match that scored 12 live replayed as 4 — the recording simply never saw most of
the swings.

The fix is the same principle ping pong already had, applied to time rather than
value: the live simulation must consume input at the **same quantised moments**
the recording stores it. `CricketMatchRunner` holds a pending input and only
promotes it to live on a sample boundary.

```dart
if (simulation.tick % sampleStride == 0) {
  _liveStriker = _pendingStriker;
  recorder.addSample(_channels());
  _pendingStriker = _withoutAction(_pendingStriker);
}
```

Stated generally, and now true of all three games: **quantise the live path, not
just the recording — in both value and time.**

---

## 8. Tests

```bash
cd packages/cricket_sim  && dart test      # 26
cd packages/game_cricket && flutter test   # 15  (11 widget + 4 golden)
```

The one that matters most is in `cricket_view_test.dart`: it plays a whole match
through the real widget with real taps on the real pads, then re-runs the replay
it produced and asserts both innings come back to the same score. If that is
green, the path from thumb to server-verifiable score is intact.

The goldens are there to be *looked at*, and they have earned their keep four
times over: the ground filling half the screen, the timing bar sitting on the
batter, three quarters of the boundary rope missing because the ellipse sweep
started inside the visible arc, and a spark burst rendering as one fifty-pixel
disc on the pitch. Not one of those failed an assertion.

There is a golden for the **bowling** innings specifically. Half the match is
played from that camera, and a view that is only wrong in the second innings is
a view nobody finds until a player does.

---

## 9. Not done

- **Sound.** There is a seam in `CricketGame._reactTo` and no assets.
- **Two-player.** Cricket is asymmetric, so pass-the-phone would mean handing
  the device over between every ball. `supportedModes` is `{vsBot}` and the
  mode-select screen offers no choice. This is the reason that field is a set.
- **Run-outs, LBW, wides, extras.** Deliberately absent. Bowled and caught are
  the two dismissals everybody understands without a rulebook.
