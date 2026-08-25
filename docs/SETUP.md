# Setup & Test

Everything runs on **Windows, natively** — no WSL, no Android Studio.

> A previous revision of this file described a WSL toolchain on a machine whose
> user was `NIB`. That is no longer how this is built. WSL has no USB
> passthrough, so it forced Wi-Fi `adb` pairing every session and gave Gradle
> only whatever RAM the VM was configured with. Native Windows gets a cable, hot
> reload, and the whole machine.

| | where | version |
|---|---|---|
| Flutter | `%USERPROFILE%\dev\flutter` | 3.47.1 (Dart 3.13.1) |
| JDK | `%USERPROFILE%\dev\jdk-17.0.20+8` | Temurin 17.0.20 |
| Android SDK | `%USERPROFILE%\dev\android-sdk` | platform 36, build-tools 36.0.0, platform-tools |

---

## 0. Install the toolchain

Already done on this machine. To reproduce it elsewhere, from PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File tools\install-toolchain.ps1
```

It downloads ~2.3 GB, extracts into `%USERPROFILE%\dev`, sets `JAVA_HOME`,
`ANDROID_HOME` and `PATH` as **user** environment variables, and installs the
SDK packages. It is idempotent — re-running skips whatever is already in place —
and logs to `%USERPROFILE%\dev\install.log`.

**Open a new terminal afterwards.** Environment variables the script sets do not
reach shells that were already running.

```powershell
flutter doctor
```

`[√] Flutter` and `[√] Android toolchain` are the two lines that matter. Chrome
and Visual Studio showing `[X]` is expected and irrelevant — we ship Android.

<details>
<summary>Two traps this script exists to avoid</summary>

**`sdkmanager --licenses` cannot be piped.** It reads from the console, so with
stdin redirected it accepts nothing, installs nothing, and still exits **0** —
indistinguishable from success until a build fails much later complaining about
a missing platform. The script writes the licence hash files directly, which is
exactly what typing "y" does.

**PowerShell reports `flutter.bat` as failed when it has not.** Flutter writes
"Building flutter tool…" to stderr, and Windows PowerShell 5.1 turns any native
command's stderr into an error record and sets the exit code to 1. The command
succeeded; the shell is misreporting it. Check for the artifact, not the exit
code.

</details>

---

## 1. Test (no phone needed)

```powershell
cd <repo root>
flutter pub get     # once, from the ROOT — this is a pub workspace, one lockfile
flutter analyze     # must print "No issues found!"
```

Then the six suites — **154 tests**:

```powershell
cd packages\game_core   ; dart test        # 24  RNG, fixed timestep, sweep, replay codec
cd ..\pingpong_sim      ; dart test        # 28  pong rules, physics, bot balance, replay verify
cd ..\racing_sim        ; dart test        # 42  track, car physics, bot ladder, replay verify
cd ..\game_pingpong     ; flutter test     #  7  widget, multi-touch, goldens
cd ..\game_racing       ; flutter test     # 14  widget, four-thumb multi-touch, replay verify, goldens
cd ..\..\app            ; flutter test     # 39  hub, mode select, rewards, layout, points ledger
```

The two that matter most are `pingpong_sim/test/simulation_test.dart` and
`racing_sim/test/simulation_test.dart`. Each plays a match, records it, replays
it, and asserts the score reproduces exactly — then confirms a forged score does
not survive. **If either goes red, no score the server receives can be
verified.**

### A note on golden tests

`packages/game_pingpong/test/golden_test.dart` compares rendered frames against
committed PNGs. **Goldens are platform-specific**: font rasterisation and
anti-aliasing differ between Linux and Windows, so images generated under WSL
did not match on Windows and that suite was red on arrival here. They have been
regenerated.

If you add CI later, either run it on `windows-latest` or exclude the golden
test on Linux — one set of images cannot satisfy both.

```powershell
cd packages\game_pingpong ; flutter test --update-goldens
```

Writes real frames to `test/goldens/*.png`. Open them — this is how the stale
"GET READY" banner bug was originally caught: no assertion found it, looking at
the picture did.

### Tune the bots

```powershell
cd packages\pingpong_sim ; dart run tool/balance.dart
cd packages\racing_sim   ; dart run tool/balance.dart    # the difficulty ladder
cd packages\racing_sim   ; dart run tool/diagnose.dart   # solo pace per difficulty
cd packages\racing_sim   ; dart run tool/cutcheck.dart   # is cutting a corner profitable?
```

---

## 2. Play it on your phone

### Fast path — sideload the APK

```powershell
cd app
flutter build apk --release
```

The APK lands at `app\build\app\outputs\flutter-apk\app-release.apk`. Copy it to
the phone over USB or Drive and tap it; Android will ask you to allow installs
from whichever app you opened it with, the first time only.

It is signed with the debug key, which is fine for sideloading and testing. A
Play Store upload needs a real keystore — a Phase 3 job.

### Better path — plug the phone in

Gives you hot reload, which is the only sane way to tune game feel.

1. On the phone: **Settings → About phone → tap "Build number" seven times**.
2. **Settings → Developer options → USB debugging**, on.
3. Plug in with a cable that carries data — many charge-only cables do not.
4. Accept the "Allow USB debugging?" prompt on the phone.

```powershell
adb devices          # should list your phone as "device", not "unauthorized"
cd app
flutter run
```

Then `r` hot-reloads, `R` restarts, `q` quits.

If `adb devices` is empty: try another cable, then another port, then
`adb kill-server ; adb start-server`.

---

## 3. What to actually test

The unit tests prove the simulations are right. These are the things only a
person holding a real phone can tell you.

**Car racing, vs bot**

- Does the car feel like it has weight, or like it is on rails?
- Is the brake worth using, or can you hold the throttle for a whole lap? If you
  can, `RaceField.lateralGripLimit` is too generous.
- Is `medium` a fair fight? `hard` should take about two races in three.
- Try **auto gas**. It may simply be the better default.

**Car racing, two players, one phone**

The important one, and the only test that tells you whether it is fun. Sit
facing each other with the phone flat between you.

- Can you both reach your buttons without elbowing?
- Does bumping the other car read as satisfying or as unfair?
- Is the rotated top band actually readable from that side?

**Points**

- Play five races; the payout should visibly shrink from the sixth.
- Force-quit the app and reopen it — the balance must survive.
- Open Rewards and check the progress bars moved.

**Both games**

- Play one of each and confirm the hub balance adds up across them. That is the
  cross-game economy working end to end.
