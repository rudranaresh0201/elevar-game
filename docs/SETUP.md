# Setup & Test

Everything below runs **inside WSL**. You do not need Android Studio, and you do
not need Flutter on the Windows side. The toolchain is already installed:

| | where | version |
|---|---|---|
| Flutter | `~/flutter` | 3.47.1 (Dart 3.13.1) |
| JDK | `~/jdk17` | Temurin 17.0.20 |
| Android SDK | `~/android-sdk` | platform 36, build-tools 36.0.0, platform-tools 37 |

`~/.bashrc` exports `JAVA_HOME`, `ANDROID_HOME` and puts `flutter`, `adb` and
`sdkmanager` on the PATH. **Open a new shell** (or `source ~/.bashrc`) before
your first command.

Verify:

```bash
flutter doctor
```

`[✓] Flutter`, `[✓] Android toolchain` are the two lines that matter. Chrome and
Linux-desktop show `[✗]` — that is expected and irrelevant; we ship Android.

---

## 1. Test (no phone needed)

```bash
cd /mnt/c/Users/NIB/Desktop/game-elevar
flutter pub get          # once, from the repo root — it is a pub workspace
flutter analyze          # must print "No issues found!"
```

Then the four suites — **68 tests**:

```bash
(cd packages/game_core    && dart test)      # 24 — RNG, fixed timestep, sweep, replay codec
(cd packages/pingpong_sim && dart test)      # 28 — rules, physics, bot balance, replay verify
(cd packages/game_pingpong && flutter test)  #  7 — widget, multi-touch, goldens
(cd app                    && flutter test)  #  9 — navigation, points estimate
```

The one that matters most is `packages/pingpong_sim/test/simulation_test.dart`:
it plays a match, records it, replays it, and asserts the score reproduces
exactly — then confirms a forged score does not survive. **If that goes red, no
score the server receives can ever be verified.**

### Look at the rendering

```bash
(cd packages/game_pingpong && flutter test --update-goldens)
```

Writes real frames to `packages/game_pingpong/test/goldens/*.png`. Open them.
This is how the stale "GET READY" banner bug was caught — no assertion found it,
looking at the picture did.

### Tune the bot

```bash
(cd packages/pingpong_sim && dart run tool/balance.dart)
```

Win rates per difficulty against a scripted human, plus rally length and match
duration. Dials live in `packages/pingpong_sim/lib/src/bot.dart`.

---

## 2. Play it on your phone

### Fast path — sideload the APK

```bash
cd app
flutter build apk --release
cp build/app/outputs/flutter-apk/app-release.apk /mnt/c/Users/NIB/Desktop/elevar.apk
```

Plug the phone into the PC, set the USB mode to **File transfer**, drag
`elevar.apk` onto the phone, tap it, allow "install unknown apps".

Signed with the debug key — fine for your own device, not for the Play Store.

### Better path — wireless debugging, with hot reload

Worth the five minutes: you get `r` to hot-reload the game while it is running
on the phone, which is the only sane way to tune game feel.

On the phone: **Settings → Developer options → Wireless debugging → on**, then
**Pair device with pairing code**. It shows an IP:port and a 6-digit code.

In WSL:

```bash
adb pair 192.168.x.x:PPPPP        # the pairing port + code from that dialog
adb connect 192.168.x.x:NNNNN     # the *other* port, on the main Wireless debugging screen
adb devices                       # should list your phone
```

The two ports are different — pairing uses a one-shot port, connecting uses the
persistent one. Phone and PC must be on the same Wi-Fi.

Then:

```bash
cd app
flutter run --release             # or omit --release while iterating
```

`r` hot-reloads, `R` restarts, `q` quits.

> Why not USB? WSL2 has no USB passthrough without installing `usbipd-win` and
> re-attaching the device on every boot. Wireless debugging avoids all of it.

---

## 3. What to actually check when you play

Phase 1's exit criterion is *"it feels good in the hand"*, which no test can
assert. Specifically:

- **Two thumbs at once.** Both paddles must move simultaneously and neither
  player can grab the other's paddle across the net.
- **The bot's three levels.** Easy should be beatable while distracted; hard
  should be genuinely hard. These are calibrated against a *scripted* opponent,
  not a person — expect to retune.
- **Ball speed at the top of a long rally.** It accelerates 8.5% per hit up to a
  ceiling. Is the ceiling too fast to react to on a real screen?
- **Serve and point-freeze pauses.** 0.7s and 0.8s. Long enough to reset, short
  enough not to annoy?

---

## Troubleshooting

**`flutter: command not found`** — new shell, or `source ~/.bashrc`.

**`Multiple adb binaries found`** — there is an older `~/.local/bin/adb`
alongside the SDK's. Both are 37.0.0 so it is harmless; delete the stray one if
the warning bothers you.

**Gradle hangs on first build** — it downloads ~200MB the first time. Later
builds are under a minute.

**`adb connect` refused** — wireless debugging turns itself off when the phone
leaves Wi-Fi or reboots. Re-enable it; you usually need to re-pair too.

**Build fails after editing a package** — the workspace shares one lockfile;
run `flutter pub get` from the **repo root**, not from `app/`.
