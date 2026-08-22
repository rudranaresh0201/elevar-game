# Elevar Play

A casual game hub. Games are played entirely **on one device** — two humans
sharing a screen, or one human against a bot. The app stays online for identity,
a single cross-game points currency, and leaderboards.

**Phase 1 is built:** ping pong, playable, fully offline, no backend.
See [`docs/PLAN.md`](docs/PLAN.md) for the full end-to-end plan.

---

## Layout

```
app/                    the Flutter application
packages/
  game_core/            ⭐ PURE DART — deterministic engine primitives
  pingpong_sim/         ⭐ PURE DART — the ping pong rules and physics
  game_pingpong/        Flame renderer + touch layer
  design_system/        colours, type, chunky controls
docs/PLAN.md            the end-to-end plan
```

The two starred packages import no Flutter and no Flame. That is what lets the
Phase 5 server worker re-run a submitted match and check its score — the same
code, unchanged, on the API box.

---

## Setup

Everything — tests **and** Android builds — runs inside WSL. Flutter, JDK 17 and
the Android SDK are installed under `~`; `~/.bashrc` puts them on the PATH. You
do not need Android Studio or Flutter on the Windows side.

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
flutter run                    # …with a phone paired over wireless debugging
```

WSL2 has no USB passthrough, so pair the phone with **adb over Wi-Fi** rather
than a cable — `docs/SETUP.md` has the two-port pairing dance. That path gives
you hot reload, which is the only sane way to tune game feel.

---

## Tests

```bash
# pure Dart — fast, no device needed
cd packages/game_core   && dart test
cd packages/pingpong_sim && dart test

# widget and golden tests
cd packages/game_pingpong && flutter test
cd app                    && flutter test
```

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
  PNG. Regenerate with `flutter test --update-goldens`.

### Tuning the bot

```bash
cd packages/pingpong_sim && dart run tool/balance.dart
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
