# Getting a link out

Two ways to hand somebody the game. They are not alternatives — ship both from
the same URL.

| | reaches | first load | caveat |
|---|---|---|---|
| **Web build** | anyone with a browser | ~6 MB gzipped, then cached | no sound, no haptics on iOS |
| **APK** | Android only | 45 MB, one-time | "unknown sources" warning |

The web build is what makes a link worth sending. The APK is what somebody
installs after they have already played once and liked it.

---

## 1. What the web build needed

Almost nothing, and that is worth writing down, because it was the one place
the architecture could have bitten.

The points ledger is SQLite. `sqflite` does not run in a browser — but
`SqlitePointsRepository` already took a `DatabaseFactory` as a constructor
argument, because the test suite needed to inject an in-process one. So the web
port is a conditional export and four lines:

```dart
// app/lib/data/ledger_platform_web.dart
pointsRepository = SqlitePointsRepository(
  databaseFactoryOverride: databaseFactoryFfiWeb,
  pathOverride: 'elevar_points.db',
);
```

Same schema, same SQL, same daily cap, same outbox — running against
`sqlite3.wasm` in a service worker, stored in IndexedDB. **Points survive a
refresh**, which is what makes the shared link a demo of the actual product
rather than a demo of three games.

The conditional export matters: `sqflite_common_ffi_web` imports
`dart:js_interop` and will not compile into an APK.

### The two files that must ship

`web/sqflite_sw.js` and `web/sqlite3.wasm`, both produced by:

```powershell
cd app
dart run sqflite_common_ffi_web:setup
```

They are committed. A deploy that loses them looks completely fine until the
first match ends and the points silently never bank — so `deploy-web.ps1`
refuses to upload without them.

---

## 2. Deploying to the droplet

```powershell
# from the repo root
.\deploy\deploy-web.ps1 -DropletHost root@<droplet-ip> -IncludeApk
```

It builds, strips the `.symbols` files (~18 MB of debug data nothing fetches),
wipes the remote root, uploads, and reloads nginx.

First time only, on the droplet:

```bash
sudo apt install nginx certbot python3-certbot-nginx
sudo mkdir -p /var/www/elevar-play
sudo cp elevar-play.conf /etc/nginx/sites-available/elevar-play
sudo ln -s /etc/nginx/sites-available/elevar-play /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
sudo certbot --nginx -d play.elevarsports.com
```

`deploy/nginx/elevar-play.conf` has the config, with gzip on (the engine is
~7 MB of wasm before compression), long cache headers on the hashed assets, and
`try_files … /index.html` so a refresh on any route still lands in the app.

**DNS:** an `A` record for `play` pointing at the droplet, before running
certbot — certbot validates over HTTP and will fail if the name does not
resolve yet.

### Serving from a subpath instead

If it has to live under an existing site rather than its own subdomain:

```powershell
.\deploy\deploy-web.ps1 -DropletHost root@<ip> -RemoteRoot /var/www/site/play -BaseHref '/play/'
```

Getting `-BaseHref` wrong gives a blank page with nothing in the console. It is
the first thing to check.

---

## 3. Testing it before it is public

The build directory is static, so anything can serve it:

```powershell
cd app\build\web
python -m http.server 8090 --bind 0.0.0.0
```

Then open `http://<your-lan-ip>:8090` on a phone on the same Wi-Fi. This is the
fastest way to feel the controls on a real touchscreen without a deploy or a
cable.

---

## 4. Known limits of the web build

- **No sound.** There are no audio assets in any build yet.
- **No haptics on iOS Safari.** `HapticFeedback` is a no-op there. Android
  Chrome is fine. The games are built so haptics are a garnish, not a signal.
- **Orientation lock and immersive mode are no-ops.** The layouts are
  portrait-first and tested at 320/390/430pt, so this is cosmetic — a landscape
  phone gets a tall letterboxed field.
- **First load is ~6 MB gzipped.** Cached hard afterwards. The boot screen in
  `web/index.html` exists so that the first two seconds are not a white page,
  which reads as broken.
- **Points are per-browser.** IndexedDB is origin-scoped and there is no server
  yet, so a balance does not follow anyone between their phone and their
  laptop. That is Phase 2 (`PLAN.md` §9) and not a web problem.

---

## 5. What this does *not* replace

The link is a demo. The real thing still wants:

- **Phase 2's server** — identity, so a balance belongs to a person rather than
  a browser, and the replay verification that makes the points real rather than
  advisory (`PLAN.md` §§8–11).
- **The Play Store build** — sound, haptics, offline, and a home-screen icon
  people actually re-open.

Ship the link now because it answers "can I try it?" today. Do not let it
become the product.
