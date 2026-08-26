# Cricket — how it works, and what had to be measured

Game three. Same shape as the other two: a pure-Dart simulation nothing can see,
a Flame renderer that can only look, and one line in the registry.

- `packages/cricket_sim/` — rules, physics, fielding, bot. No Flutter, no Flame.
- `packages/game_cricket/` — the ground, the pads, the sparks.
- `app/lib/screens/cricket_*.dart` — mode select and the host screen.

If you only read one section, read §5. Seven separate things in this game came
out **backwards** and every one of them was found by running numbers, not by
reading code. The largest — §5.6 — is why the game had no boundaries in it for
a week.

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

**Depth culling is not enough to keep the foreground clear.** Standing behind
the striker, the keeper (y 1012) and slip (1000) are only a little nearer than
the batter, so they survive `minDepth` and then fill the bottom of the screen
with their backs. `showsSomeoneAt` drops anybody behind the striker's crease
outright: they are over your own shoulder in real life and they belong off
screen.

**A drawn player is 120 field units tall, which is a seventeen-metre human.**
Life size is about twelve units against a 468-unit ground radius, and at twelve
units nobody is visible at all. But the first attempt used 178 and the result
was a screen full of enormous people with a cricket ground somewhere behind
them.

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

Batting is **drag and release, against an armed shot**. The direction of the
drag is where the ball goes, its length is how hard, and the moment of release
is the timing. A plain tap is a zero-length drag, which falls out as a straight
push in the middle of the armed band — the correct beginner shot, and nobody
has to be told.

### The three shots

`BLOCK` · `GROUND` · `LOFT`, as three chunky buttons under the pad. Each is a
power band that the drag length runs across:

| | power | what it does |
|---|---|---|
| `BLOCK` | 0.10–0.22 | along the deck, no risk, no reward |
| `GROUND` | 0.30–0.56 | through the gap. Fours live here |
| `LOFT` | 0.62–1.00 | over the top. Sixes live here, and so do the catches |

The first version folded loft into drag length and nothing else. That was one
control too clever: the decision with the *risk* in it — deck or air — was
buried in how far a thumb happened to travel, so nobody ever made it
deliberately and every innings came out the same. Splitting it out is what
every mobile cricket game does, and it is right for the same reason.

Everything else stays in the one gesture. A direction stick, a power slider and
a swing button would be three targets for one thumb and turn every ball into an
admin task.

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

## 5. Seven things that came out backwards

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

**5.6 — Every fielder chased the ball, so nothing was ever a boundary.** All ten
ran at the predicted landing point, which meant somebody was always underneath
it: catches ran at 13–29% *of deliveries*, wickets at four and a half an innings
out of six, and hitting the ball harder only chose which fielder took it. A
two-over innings was twelve singles.

Two changes fixed it, and both are just "make it like real cricket":

* **One chaser.** The nearest fielder runs; everyone else holds position and
  stops only what comes to them. Standing still is not the same as being a hole
  in the field, so a shot straight at cover is still a shot straight at cover.
* **`fielderSpeed` 178 → 78.** At 178 units/s a fielder covered forty metres
  during a one-and-a-half-second flight, which is roughly twice the world
  record. 78 is a person.

Catches fell to 5–11% of balls and boundaries went from one in eight to one
scoring shot in three. This is the change the whole game turned on.

**5.7 — Accurate bowling was punished.** The bot's shot direction is a unit
vector, so its x can never exceed 0.707 for anything played down the ground —
but it was compared against a bare ratio capped at 1. A wide ball could
therefore never be *aligned with* however well it was read, and a straight one
aligned almost for free. Against the hard bot, a bowler at skill 0.9 conceded 34
off twelve balls and a bowler at skill 0.3 conceded 22. The whole ladder
inverted on one line comparing two different spaces.

---

## 6. The ladder

`dart run tool/diagnose.dart`, 60 matches per cell, scripted human proxy:

`dart run tool/diagnose.dart`, 150 matches per cell, scripted human proxy:

| bot | skill 0.3 | 0.6 | 0.9 | runs | 4s | 6s |
|---|---|---|---|---|---|---|
| easy | 71% | 93% | 98% | 21–34 | 17–34% | 7% |
| medium | 36% | 63% | 79% | 21–34 | 21–35% | 8–11% |
| hard | 35% | 45% | 70% | 21–33 | 21–33% | 9–15% |

Monotonic down every column and across every row, which is the property
`test/balance_test.dart` asserts. A skilled player beats easy nearly always and
hard about seven times in ten; a beginner wins around a third against anything,
which is deliberate — losing every match in the first two minutes is not a
funnel.

**About one scoring shot in three is a boundary, and a two-over innings is
20–34.** Those numbers were tuned *up*, hard, and §5.6 is the story of why they
had to be. This is a game on a shoe brand's app played by someone who did not
come for cricket; the fours and sixes are the entire reason they play a second
match. `test/balance_test.dart` now asserts the boundary share directly rather
than trusting the eye.

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
cd packages/cricket_sim  && dart test      # 27
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
