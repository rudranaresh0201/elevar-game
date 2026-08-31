# Elevar Play

A casual game hub. Games are played entirely **on one device** — two humans
sharing a screen, or one human against a bot. The app stays online for identity,
a single cross-game points currency, and leaderboards.

**Four games are built and playable, fully offline:** soccer, cricket, car
racing and ping pong. Points are banked in a real on-device ledger and queued
for a server that does not exist yet.

The app also has a **player profile** and a **leaderboard**. The board is fed by
a webhook whose URL is compiled in at build time; with no URL it says so
plainly and shows the player their own totals instead of an empty list.

- [`docs/PLAN.md`](docs/PLAN.md) — the full end-to-end plan
- [`docs/SOCCER.md`](docs/SOCCER.md) — the soccer build, and why the input
  encoding had to be rebuilt
- [`docs/RACING.md`](docs/RACING.md) — how the racing game works, and the two
  things that had to be measured rather than reasoned about
- [`docs/CRICKET.md`](docs/CRICKET.md) — the cricket build, the seven things
  that came out backwards, and the §9 rebuild that replaced the timing window
  with a bat you hold
- [`docs/LEADERBOARD.md`](docs/LEADERBOARD.md) — the webhook contract, and what
  the server has to do before the numbers on it can be trusted
- [`docs/DEPLOY.md`](docs/DEPLOY.md) — getting a playable link out: the web
  build, the droplet, and what the browser cannot do

---

## Layout

```
app/                    the Flutter application
  lib/games/            ⭐ the game plugin contract + registry
  lib/data/             ⭐ the points ledger, per-game stats, sync outbox
  lib/screens/          ⭐ the shell, the hub, the board, the profile
packages/
  game_core/            ⭐ PURE DART — deterministic engine primitives
  pingpong_sim/         ⭐ PURE DART — the ping pong rules and physics
  racing_sim/           ⭐ PURE DART — the racing rules, track and physics
  cricket_sim/          ⭐ PURE DART — the cricket rules, fielding and bot
  soccer_sim/           ⭐ PURE DART — the table-soccer rules, physics and bot
  game_pingpong/        Flame renderer + touch layer
  game_racing/          Flame renderer + the four-button control bands
  game_cricket/         Flame renderer + the crease pad and the blade
  game_soccer/          Flame renderer + the slingshot band
  design_system/        colours, type, chunky controls
docs/*.md               the plan, and one build note per game
```

**Adding a game touches two files.** An `ElevarGame` implementation and a line
in `app/lib/games/registry.dart`. The hub, the result screen, the points formula
and the ledger never learn that it exists — every game reduces to a
`GameResult`, and the payout only ever reads `normalizedSkill`. That contract
was specified in `PLAN.md` §4 from the start and built when racing arrived,
because an interface derived from one implementation is a description of that
implementation. Cricket is the proof it was real: a game with a different shape
entirely — an innings, two roles, one player — cost the hub exactly one line.

The starred simulation packages import no Flutter and no Flame. That is what
lets the Phase 5 server worker re-run a submitted match and check its score —
the same code, unchanged, on the API box.

---

## Setup

Everything runs on **Windows**, natively. Flutter 3.47.1, JDK 17 and the Android
SDK live under `C:\Users\<you>\dev`. You do not need Android Studio and you do
not need WSL — which also means `adb` over a USB cable just works, and so does
hot reload.

> Earlier revisions of this file described a WSL toolchain. That was the setup
> on a different machine; WSL has no USB passthrough, so it forced Wi-Fi pairing
> every session.

See **[`docs/SETUP.md`](docs/SETUP.md)** for the full walkthrough, including
getting the game onto a phone.

```bash
flutter doctor           # [✓] Flutter and [✓] Android toolchain are the lines that matter
flutter pub get          # from the repo ROOT — this is a pub workspace, one lockfile
flutter analyze          # must be clean
```

---

## Running it

```bash
cd app
flutter build apk --release    # sideload the APK, or…
flutter run                    # …with a phone plugged in over USB
```

It also builds for the **web**, which is how anybody gets a link they can just
tap. The points ledger runs the same SQL against `sqlite3.wasm` in the browser,
so a balance survives a refresh:

```bash
cd app
flutter build web --release
.\..\deploy\deploy-web.ps1 -DropletHost root@<ip> -IncludeApk
```

See [`docs/DEPLOY.md`](docs/DEPLOY.md).

`flutter run` gives you hot reload, which is the only sane way to tune game
feel. [`docs/SETUP.md`](docs/SETUP.md) has the full walkthrough, including
getting the phone to show up.

---

## Tests

```bash
# pure Dart — fast, no device needed
cd packages/game_core    && dart test    # 24
cd packages/pingpong_sim && dart test    # 28
cd packages/racing_sim   && dart test    # 44
cd packages/cricket_sim  && dart test    # 27
cd packages/soccer_sim   && dart test    # 26

# widget and golden tests
cd packages/game_pingpong && flutter test  #  7
cd packages/game_racing   && flutter test  # 17
cd packages/game_cricket  && flutter test  # 17
cd packages/game_soccer   && flutter test  #  7
cd app                    && flutter test  # 66
```

263 tests, all green.

### What the tests are actually for

- **`packages/game_core/test/determinism_test.dart`** — the RNG and the fixed
  timestep. Everything else rests on these.
- **`packages/pingpong_sim/test/simulation_test.dart`** — the golden test:
  *given a seed and an input log, the match reproduces exactly.* It also
  replays a recorded match and confirms a forged score does not survive.
  **If this file ever goes red, no score the server receives can be verified.**
- **`packages/pingpong_sim/test/balance_test.dart`** — the difficulty curve is
  monotonic and every match terminates.
- **`packages/game_pingpong/test/pong_view_test.dart`** — plays a whole match
  through the real widget with a real dragged finger, then verifies the replay
  it produced.
- **`packages/game_pingpong/test/golden_test.dart`** — renders actual frames to
  PNG. Regenerate with `flutter test --update-goldens`. Goldens are
  platform-specific: these were regenerated on Windows, and will differ if you
  ever run them on Linux.
- **`packages/racing_sim/test/simulation_test.dart`** — the same golden
  determinism and replay-verification guarantee, for racing.
- **`packages/racing_sim/test/balance_test.dart`** — the difficulty ladder is a
  slope rather than a cliff, and every race terminates. See
  [`docs/RACING.md`](docs/RACING.md) §5 for why that test exists.
- **`packages/game_racing/test/race_view_test.dart`** — plays through the real
  widget with real thumbs, including four buttons at once, then verifies the
  replay it produced.
- **`packages/cricket_sim/test/simulation_test.dart`** — determinism and replay
  verification again, plus the scoring rule that was inverted for a day:
  [`docs/CRICKET.md`](docs/CRICKET.md) §4.1.
- **`packages/cricket_sim/test/balance_test.dart`** — the ladder is monotonic in
  both directions and every innings terminates. Sample sizes are large on
  purpose: a two-over innings is noisy enough that a 30-match monotonicity
  assertion fails on chance while the slope underneath it is clean.
- **`packages/soccer_sim/test/simulation_test.dart`** — determinism, replay
  verification, and the physics bounds: nothing tunnels a touchline at the
  speed cap, a ball in the mouth is a goal and a ball beside it is not, and a
  counter never leaves through a goal.
- **`packages/game_soccer/test/soccer_view_test.dart`** — a real thumb on the
  real pitch. Includes the fast-flick regression: down, drag and up inside two
  frames still takes the shot.
- **`app/test/leaderboard_test.dart`** — the webhook parser against the four
  response shapes an automation is likely to emit, and the profile store
  against real SQL.
- **`packages/game_cricket/test/cricket_view_test.dart`** — a whole match played
  through the real pads with real taps, then replayed and checked to the run.
  Also asserts the view is a perspective one: the pitch has to be wider at the
  batter's end than the bowler's, which is what the original top-down render
  failed.
- **`app/test/layout_test.dart`** — every screen built at 320, 390 and 430pt. A
  Flutter overflow is a `FlutterError` during layout, so building it is the
  assertion.
- **`app/test/points_repository_test.dart`** — the ledger. Sum of every delta
  equals the balance, the daily cap holds, diminishing returns diminish, and a
  zero-paying match is still auditable.

### Tuning the bot

```bash
cd packages/pingpong_sim && dart run tool/balance.dart
cd packages/soccer_sim   && dart run tool/balance.dart
cd packages/cricket_sim  && dart run tool/diagnose.dart
```

Prints win rates for a scripted human of varying skill against each difficulty,
plus average rally length and match duration. Current numbers:

| bot | skill 0.35 | 0.60 | 0.85 | 1.00 | avg rally | avg secs |
|---|---|---|---|---|---|---|
| easy | 92% | 99% | 100% | 100% | 5.5 | 83 |
| medium | 18% | 71% | 98% | 100% | 10.3 | 130 |
| hard | 0% | 8% | 63% | 100% | 13.9 | 157 |

These come from a scripted opponent, not people. **Retune against real players
before launch** — the dials are all in `packages/pingpong_sim/lib/src/bot.dart`.

---

## The rules that keep this verifiable

Break any of these and server-side replay verification silently stops working.

1. **`game_core` and `pingpong_sim` never import Flutter.** They must run
   headless on a server.
2. **No trigonometry in the simulation.** `sin`/`cos`/`atan2` come from the
   platform's libm and are not guaranteed identical across architectures. All
   direction maths is vector maths; `sqrt` is safe because IEEE-754 requires it
   to be correctly rounded.
3. **No `dart:math` `Random`.** Use `DeterministicRng`, seeded from the match
   nonce, and take a separate stream per consumer.
4. **The simulation never reads a clock.** It advances in fixed ticks only.
5. **Input is quantised on the live path, not just in the recording** — see
   `PongMatchRunner`. A match recorded at lower precision than it was played is
   a match that cannot be reproduced.
