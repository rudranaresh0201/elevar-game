# The leaderboard, and what has to be true before it means anything

The hub was per-*device* until this existed: one balance, no name, nothing to
put on a board. There are now three pieces — an identity, a webhook, and a
cache — and one important caveat about trust.

- `app/lib/data/player_profile.dart` — the model
- `app/lib/data/profile_repository.dart` — the identity and the cached board
- `app/lib/data/leaderboard_client.dart` — the webhook and its parser
- `app/lib/data/leaderboard_service.dart` — the three states the screen shows
- `app/lib/screens/leaderboard_screen.dart` — the board
- `app/lib/screens/profile_screen.dart` — the name and avatar

---

## 1. Identity, without a sign-up wall

A `playerId` is generated once on the device and never changed. It is **not an
account**. Elevar has no server to log into yet, and inventing one now would put
a registration wall in front of a game — the most reliable way to lose somebody
who arrived from an Instagram link.

The id is what a real account will later be *attached to*, so the points a
player earns before signing in are not lost when they do. That is the whole
reason it is a stable random id rather than something derived from the install.

The display name defaults to `Player 4821`. The profile screen nudges players
who still have a default one and leaves everyone else alone, because a board
full of `Player 4821` is a board nobody wants to be on.

---

## 2. The webhook

One POST. It submits and returns in the same round trip, so the board a player
sees always already contains the match they just finished — which is the moment
they actually care where they are.

```
POST $ELEVAR_LEADERBOARD_WEBHOOK
Content-Type: application/json
X-Elevar-Key: $ELEVAR_LEADERBOARD_KEY   (optional)

{
  "playerId":      "9f2c…",       // 32 hex chars, stable per device
  "displayName":   "Rudra",       // ≤ 18 chars, trimmed
  "avatarIndex":   3,
  "lifetimePoints": 4820,
  "balance":        1200,
  "streakDays":     7,
  "matchesPlayed":  61,
  "submittedAt":   "2026-08-31T12:04:11.000Z"
}
```

Configured at build time, never committed:

```bash
flutter build apk --release \
  --dart-define=ELEVAR_LEADERBOARD_WEBHOOK=https://…/webhook/leaderboard \
  --dart-define=ELEVAR_LEADERBOARD_KEY=…
```

A compile-time constant rather than a runtime setting, because an endpoint a
player can change is an endpoint a player can point at their own server — and
the whole reason the board exists is that its numbers get redeemed for vouchers.

### 2.1 What it may return

Deliberately tolerant. The thing on the other end is going to be an automation
someone wired up in an afternoon, and the app should not be the reason it has to
be rewritten. All four of these parse:

```json
{"you": {"rank": 42}, "top": [ … ]}
{"rows": [ … ]}          // or "leaderboard", "data", "results"
[ … ]                    // a bare array
```

Per row, any of `playerId` / `player_id` / `id`, `displayName` /
`display_name` / `name` / `player`, `points` / `ep` / `score` / `total`, and
`rank` / `position`. Numbers may arrive as strings, because a sheet exports
everything as text. A missing rank is derived from the ordering, so a sheet that
simply returns its rows sorted works with no extra columns.

Anything that is not a board — an HTML error page, a bare `{"ok": true}` — is
refused rather than guessed at, and the screen falls back to its cache.

`app/test/leaderboard_test.dart` pins every one of those shapes. A new one
showing up should be a test there, not a crash on somebody's phone.

---

## 3. Lifetime points, not balance

The board ranks on **lifetime** points — every point ever earned, before
anything was spent.

Ranking on the spendable balance would put the rewards shop and the leaderboard
in direct competition: redeeming a voucher would cost you your place, and the
player would have to choose between the two things the app is for.

---

## 4. Three states, and the screen says which

| state | when | what the player sees |
|---|---|---|
| **live** | fetched just now | the board |
| **stale** | the network did not answer | the last board we had, with its age on it |
| **not connected** | no endpoint compiled in | an honest note, and their own totals |

None of them is a spinner that never resolves and none is an empty list. A board
silently showing yesterday is worse than one that says it is showing yesterday.

"Not connected" is the default in any build without the `--dart-define`, which
means it is the state every developer sees — so it had to read as *not yet*
rather than as *broken*.

---

## 5. The caveat, and it is the important part

**The server must treat every submitted total as a claim.**

`X-Elevar-Key` is a doorbell, not authentication. Anything baked into an APK can
be read out of it in about a minute. A phone that posts
`{"lifetimePoints": 999999}` will be believed by any webhook that does not check.

The real defence already exists in this repo and is not wired up yet: every
match banks a **replay** in the outbox (`docs/PLAN.md` §9), and every simulation
package is pure Dart specifically so the same code can re-run a submitted match
headlessly and derive the score itself. The board should be built from matches
the server re-simulated — not from a number the phone sent.

Until that exists, treat the leaderboard as a **marketing display**, and do not
let a voucher be issued off a rank alone.

---

## 6. What is deliberately absent

- **Friends, teams, seasons.** All reasonable, all a product decision rather
  than a plumbing one, and all cheaper to add once there is a real server.
- **Pushing on every match.** The board is fetched when the tab is opened. A
  submission per match would multiply the webhook's traffic by about forty for
  a number nobody is looking at.
- **A second database.** The profile and the cached board live in
  `elevar_social.db`, separate from the points ledger, because one is a cache
  and the other is a book of record. Every schema change to a cache kept inside
  a ledger is a migration against money.
