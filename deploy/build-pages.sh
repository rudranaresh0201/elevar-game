#!/usr/bin/env bash
# Build the whole public site into one folder:
#
#   <out>/                 landing page (site/), picks the right button per phone
#   <out>/play/            the game, as a web app — this is the iPhone version
#   <out>/elevar-play.apk  the Android app
#
#   deploy/build-pages.sh _site https://rudranaresh0201.github.io/elevar-game/
#
# CI runs exactly this (.github/workflows/ship.yml), so a local run is a real
# preview of the deploy. FLUTTER overrides the flutter command, for machines
# where `flutter` is not on PATH. Set SKIP_APK=1 to iterate on the web side.

set -euo pipefail

out="${1:?usage: build-pages.sh <out-dir> <site-url>}"
site_url="${2:?usage: build-pages.sh <out-dir> <site-url>}"
flutter="${FLUTTER:-flutter}"

site_url="${site_url%/}/"
# The path part of the URL, e.g. /elevar-game/. Getting the base href wrong
# gives a blank page with nothing in the console, so derive it, never type it.
base="$(printf '%s' "$site_url" | sed -E 's#^https?://[^/]+##')"
[ -n "$base" ] || base="/"

repo="$(cd "$(dirname "$0")/.." && pwd)"
app="$repo/app"
mkdir -p "$out"
out="$(cd "$out" && pwd)"

defines=()
if [ -f "$app/elevar.env.json" ]; then
  defines=(--dart-define-from-file=elevar.env.json)
else
  echo "warning: app/elevar.env.json missing — the leaderboard will read 'not connected'" >&2
fi

build_number="${BUILD_NUMBER:-1}"

echo "==> web build (base href ${base}play/)"
(cd "$app" && $flutter build web --release --base-href "${base}play/" "${defines[@]}")

# Both files are load-bearing and easy to lose; without them points silently
# never bank in a browser. See docs/DEPLOY.md.
for f in sqflite_sw.js sqlite3.wasm; do
  [ -f "$app/build/web/$f" ] || { echo "error: build/web/$f missing" >&2; exit 1; }
done

rm -rf "$out"
mkdir -p "$out/play"
cp -R "$app/build/web/." "$out/play/"
# Leftovers from older local builds and debug data nothing fetches.
rm -f "$out/play/"*.apk
find "$out/play" -name '*.symbols' -delete

cp -R "$repo/site/." "$out/"

apk_size="Android 7+"
if [ "${SKIP_APK:-0}" != "1" ]; then
  echo "==> apk build (build number $build_number)"
  (cd "$app" && $flutter build apk --release --build-number "$build_number" "${defines[@]}")
  cp "$app/build/app/outputs/flutter-apk/app-release.apk" "$out/elevar-play.apk"
  apk_size="$(( ($(wc -c < "$out/elevar-play.apk") + 524288) / 1048576 )) MB"
fi

build="$(git -C "$repo" rev-parse --short HEAD 2>/dev/null || echo local) · $(date -u +%Y-%m-%d)"
sed -i.bak \
  -e "s#__SITE_URL__#${site_url}#g" \
  -e "s#__APK_SIZE__#${apk_size}#g" \
  -e "s#__BUILD__#${build}#g" \
  "$out/index.html"
rm -f "$out/index.html.bak"

echo "==> site ready in $out"
