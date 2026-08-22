# Elevar Play — End-to-End Build Plan

**Status:** v1.1 · 2026-08-21 · **Phase 0 and Phase 1 are built** (see `README.md`)
**Decisions locked:** Flutter + Flame · Phone SMS OTP (India-first) · Android first · DigitalOcean

---

## 1. Context

Elevar Play is a casual mobile game hub: 3–4 simple games, starting with a two-player
ping pong. Every game is played **entirely on one device** — either two humans sharing
the screen, or one human against a computer bot. There is no network gameplay.

The app is nonetheless **online**: accounts, a single cross-game points currency,
leaderboards, and live score sync all live on a server. Points are intended to become
redeemable for D2C brand vouchers/tokens later, which means **points are money-adjacent
from day one** and must be treated with the rigour of a financial ledger, not a counter
on a user row.

### The one architectural insight that shapes everything

Because gameplay is offline, **server load is proportional to matches *submitted*, not
minutes *played*.** A 20-minute session costs the server exactly one POST and one
websocket push. This is why this design scales cheaply:

| Scale | Matches/day | Avg writes/sec | Peak writes/sec | Infra needed |
|---|---|---|---|---|
| 1k DAU | 8k | 0.1 | ~1 | 1 × $5 instance |
| 100k DAU | 800k | 9 | ~50 | 2 × $12 instances |
| 1M DAU | 8M | 93 | ~500 | 4–6 instances + read replica |

A single 2-vCPU Fastify process handles ~2,000 simple writes/sec. **You will hit SMS
cost limits long before you hit compute limits.** Plan accordingly.

The corollary: because the client is untrusted and produces the scores that become
money, **anti-abuse — not throughput — is the hard engineering problem here.**

---

## 2. Stack

### 2.1 Mobile — Flutter + Flame

| Concern | Choice | Why |
|---|---|---|
| Framework | Flutter (stable channel) | Single codebase, Android-first now, iOS later at near-zero cost |
| Game engine | `flame` | Mature 2D loop, components, sprites, audio, collision |
| Physics | **Hand-rolled, not `flame_forge2d`** | See §5.2 — determinism is required for replay verification. Box2D ports are not reliably deterministic; pong physics is 100 lines |
| State | `riverpod` 3.x | Async-first, testable, the 2026 default for new Flutter apps |
| Navigation | `go_router` | Deep links for referrals/vouchers later |
| Local DB | `drift` (SQLite) | Relational — needed for the offline outbox, local match history, cached leaderboard |
| Networking | `dio` + interceptors | Auth refresh, retry, idempotency headers |
| Secrets | `flutter_secure_storage` | Keystore-backed refresh tokens |
| Models | `freezed` + `json_serializable` | Immutable, exhaustive unions for game state |
| Audio | `flame_audio` | Paddle hits, wall bounce, score |
| Monorepo | Dart **pub workspaces** | One `pub get`, one lockfile, local path deps. Supersedes what melos was for; melos is no longer needed |

### 2.2 Backend — Node 22 + TypeScript + Fastify

| Concern | Choice | Why |
|---|---|---|
| Runtime | Node 22 LTS | *(local machine has Node 18 — upgrade)* |
| Framework | Fastify | Fast, schema-first (JSON Schema → validation + typed routes + OpenAPI for free) |
| ORM | `drizzle-orm` | SQL-first, no runtime engine, transparent transactions — essential for ledger work |
| DB | Postgres 16 (DO Managed) | ACID transactions are non-negotiable for a points ledger |
| Cache/Realtime | Valkey (DO Managed Redis) | Session tokens, rate limits, leaderboard sorted sets, WS pub/sub |
| Jobs | BullMQ (on Valkey) | Streak rollups, leaderboard snapshots, verification, push |
| Auth | Custom OTP → JWT | MSG91 sends the SMS; no reason to pay Firebase to wrap it |
| Object store | DO Spaces + CDN | Replay blobs, game assets, avatars |
| Realtime | `ws` + Redis pub/sub adapter | Leaderboard and balance push |
| Logging | `pino` → structured JSON | Forwarded to Better Stack / Axiom |
| Errors | Sentry (app + API) | |

**Why not Supabase/Firebase?** Both are excellent for CRUD apps. Neither is a good home
for an append-only financial ledger with server-only reward formulas and custom anti-abuse
rules — you'd end up writing edge functions that *are* this backend, but with less control
over transactions and a vendor-shaped data model. Also, Supabase Realtime is priced by
concurrent connections and you'd renegotiate above ~500. Owning a Fastify service on
infra you already pay for is both cheaper and less constrained here.

**Why not a Dart backend (Serverpod / Dart Frog)?** Tempting — one language, and you could
share the physics package directly with the server for replay verification. But the backend's
real work is OTP providers, ledgers, payments, voucher-partner APIs and observability, where
the TypeScript ecosystem is years ahead. Resolution: **TS for the API, and a small Dart
verifier worker in Phase 5** that imports the *same* `game_core` package the app uses.
Best of both, deferred until it's actually needed.

### 2.3 Infrastructure — DigitalOcean

```
                    ┌──────────────────────┐
   Play Store ──▶   │  Flutter app (APK)   │
                    └──────────┬───────────┘
                        HTTPS  │  WSS
                    ┌──────────▼───────────┐
                    │  DO App Platform     │   api.elevarplay.com
                    │  Fastify × 2 (auto)  │   ← stateless, horizontal
                    └───┬──────────┬───────┘
                        │          │
          ┌─────────────▼───┐  ┌───▼──────────────┐
          │ Managed Postgres│  │ Managed Valkey   │
          │ 16 · 1GB → HA   │  │ sessions, ZSETs, │
          │ daily backups   │  │ pub/sub, BullMQ  │
          └─────────────────┘  └──────────────────┘
                        │
          ┌─────────────▼───────────────┐
          │ DO Spaces + CDN             │  replays/, assets/, avatars/
          └─────────────────────────────┘

  External: MSG91 (SMS OTP) · Sentry · Better Stack · FCM (push)
```

**App Platform over raw Droplets** for the API: zero server admin, free managed TLS,
GitHub-push deploys, built-in horizontal scaling. Droplets are ~30% cheaper at equivalent
specs but cost you deployment tooling, TLS renewal, OS patching, and an on-call story —
a bad trade for a small team. Revisit at >$300/mo spend.

**Starting monthly cost (~$62):**

| Item | Cost |
|---|---|
| App Platform · API 2 × basic | $24 |
| Managed Postgres 1GB single node | $15 |
| Managed Valkey 1GB | $15 |
| Spaces + CDN 250GB | $5 |
| Staging app + dev DB | ~$12 |
| Sentry / Better Stack | free tiers |
| **Total** | **~$62–71/mo** |

Add HA Postgres standby (+$15) before public launch. SMS is variable: at ₹0.20/OTP,
50k signups ≈ ₹10,000.

**Environments:** `local` (docker compose) → `staging` (DO, seeded data, test SMS) →
`prod`. Infra defined in Terraform (`infra/`) so environments are reproducible.

### 2.4 Local dev environment — important WSL note

The repo lives on the Windows filesystem (`C:\Users\NIB\Desktop\game-elevar`), and
**Flutter Android development should run on Windows natively, not inside WSL2** — WSL
has no clean USB/adb passthrough and no hardware-accelerated emulator. Install Flutter +
Android Studio on Windows and point them at this same folder.

The **backend** is the opposite: run it in WSL2 (or Docker Desktop) where Node/Postgres/
Redis behave properly. Both halves of the monorepo, one folder, two toolchains. This
works fine — just don't try to run `flutter build` from WSL.

**Status:** the Flutter SDK is installed in WSL and runs `analyze` and the whole
test suite there. Still to install *on Windows*, to produce an APK: Android
Studio, Android SDK 35, JDK 17. Backend side, still to install: Node 22 (the
machine has 18), Docker, `doctl`.

---

## 3. Repository layout

```
game-elevar/
├── pubspec.yaml               pub workspace root
├── README.md
├── docs/
│   ├── PLAN.md                    ← this file
│   ├── ARCHITECTURE.md
│   └── ADR/                       decision records
├── app/                           the Flutter application shell
│   ├── lib/
│   │   ├── main.dart
│   │   ├── router.dart
│   │   ├── features/
│   │   │   ├── auth/              phone entry, OTP, profile setup
│   │   │   ├── home/              game grid, points header, streak
│   │   │   ├── leaderboard/
│   │   │   ├── profile/
│   │   │   └── rewards/           Phase 5 placeholder
│   │   ├── sync/                  outbox worker, connectivity, token vault
│   │   └── data/                  drift DB, repositories
│   └── android/
├── packages/
│   ├── game_core/                 ⭐ PURE DART. No Flutter import.
│   │   ├── deterministic fixed-step simulation loop
│   │   ├── seeded RNG (xorshift128)
│   │   ├── vector/collision maths
│   │   ├── GameResult + GameContract interfaces
│   │   └── replay recorder/player
│   │        └─ later imported verbatim by the Dart verifier worker
│   ├── pingpong_sim/              ⭐ PURE DART. The pong rules and physics.
│   │    └─ split out from game_pingpong during the build: the
│   │       renderer package depends on Flutter, so the simulation
│   │       could not live in it and still run on a server
│   ├── game_pingpong/             Flame renderer + touch layer
│   ├── design_system/             colours, type, buttons, the "chunky" theme
│   └── api_client/                generated from the API's OpenAPI spec
├── server/
│   ├── src/
│   │   ├── routes/                auth, matches, points, leaderboard, me
│   │   ├── domain/
│   │   │   ├── ledger.ts          ⭐ the only module that writes points
│   │   │   ├── scoring.ts         ⭐ versioned EP formula (server-only)
│   │   │   └── antiabuse.ts       plausibility rules, flags
│   │   ├── db/schema.ts           drizzle schema
│   │   ├── db/migrations/
│   │   ├── ws/
│   │   └── jobs/
│   └── test/
├── infra/                         terraform: DO app, db, valkey, spaces, dns
└── .github/workflows/             ci.yml, deploy-api.yml, build-android.yml
```

The `game_core` / `pingpong_sim` / `game_pingpong` split is the load-bearing
decision: **the simulation knows nothing about rendering.** That's what makes it
unit-testable, headlessly re-runnable on a server, and reusable for games 2–4.

One rule enforces it: the first two packages declare no Flutter dependency at
all, so importing it is a resolution error rather than a code review note.

---

## 4. Game plugin contract (built once, reused 4×)

Every game implements one interface, so the hub, scoring, and sync never change when
you add a game:

```dart
abstract class ElevarGame {
  String  get slug;              // 'ping_pong'
  String  get title;
  GameModes get supportedModes;  // local2P, vsBot

  Widget build(GameConfig config);            // the Flame widget
  Stream<GameResult> get results;
}

class GameResult {
  final String slug;
  final GameMode mode;
  final BotDifficulty? difficulty;
  final int durationMs;
  final int p1Score, p2Score;
  final Outcome outcome;         // p1Win | p2Win | draw
  final double normalizedSkill;  // 0.0–1.0, game-defined, comparable across games
  final ReplayBlob? replay;      // compressed input log
  final String sessionToken;     // signed, obtained from server
}
```

`normalizedSkill` is the universal translator. Ping pong derives it from average rally
length and score margin; a future puzzle game derives it from time-to-solve percentile.
The server's EP formula only ever sees this normalized number — so **the scoring economy
never needs to learn about new games.**

---

## 5. Ping Pong — game specification

### 5.1 Feel and rules

- **Orientation:** portrait. Table fills the screen, split by a centre net line.
- **Layout:** bottom half = P1 (red), top half = P2 (blue). P2's score UI is rotated 180°
  so the opposite player reads it right-way-up — matching the reference art.
- **Control:** each player drags a paddle *within their own half* (2-axis, air-hockey
  style). 2-axis beats classic 1-axis pong on touch: it gives the player something to do
  and makes near-net play tense.
- **Ball:** speeds up ~3% per rally hit, capped. Return angle is a function of *(a)* hit
  offset from paddle centre and *(b)* paddle velocity at contact — that second term is
  what makes it feel skilful rather than random.
- **Scoring:** first to 11, win by 2. "Quick match" variant: first to 7.
- **Modes:** `local2P` (two humans, one device) · `vsBot` (easy / medium / hard).
- **Juice:** screen shake on hard hits, particle burst on scoring, paddle squash on
  contact, rising pitch as rally lengthens. This is most of what makes a simple game
  feel good — budget real time for it.

### 5.2 Simulation — deterministic by construction

```
fixed timestep: 120 Hz simulation, decoupled from 60 fps render (accumulator pattern)
RNG:            seeded xorshift128, seed = server-issued sessionToken nonce
collisions:     circle-vs-AABB analytic sweep (no tunnelling at high ball speed)
state:          plain Dart doubles, IEEE-754 — same ops order ⇒ same result everywhere
inputs:         paddle positions sampled at 20 Hz, delta-encoded, gzipped
```

Given `(seed, inputLog)`, the simulation reproduces the exact final score. This costs
almost nothing to build now and is what makes Phase 5 server-side replay verification
possible at all. **This is why we avoid Forge2D** — a Box2D port gives us physics we
don't need in exchange for determinism we can't verify.

A 3-minute match's replay blob is ~4 KB gzipped. Store it in Spaces; it's cheap
insurance.

**Built, with one thing the plan had not anticipated.** Recording at 20 Hz and
16-bit precision is not enough on its own: the *live* match must also consume
input at that precision and cadence, or the recording describes a slightly
different match than the one played, and a simulation amplifies "slightly" into
a different score. `PongMatchRunner` owns that quantisation for both paths.

### 5.3 Bot AI

Difficulty is four dials, not four algorithms:

| Dial | Easy | Medium | Hard |
|---|---|---|---|
| Reaction delay | 260 ms | 140 ms | 60 ms |
| Max paddle speed | 55% | 80% | 105% of human-reachable |
| Tracking error (σ) | 70 px | 30 px | 8 px |
| Bounce prediction | none (chases ball) | 1 wall bounce | full intercept solve |
| Deliberate miss rate | 18% | 7% | 1.5% |

Deliberate imperfection matters: a bot that plays perfectly isn't hard, it's unplayable.
Hard should be beatable ~35% of the time by a good player — that's what keeps the EP
reward for beating it meaningful.

**Measured, and the dials moved.** `tool/balance.dart` plays a scripted human
against each bot a few hundred times; the shipped numbers are in `README.md`.
Two corrections came out of it. Giving Easy no bounce prediction at all made the
curve a cliff rather than a slope — every difficulty now anticipates, and they
differ by *how far and how accurately*. And the shipped values are calibrated
against a scripted opponent, not people: **retune against real players before
launch.**

---

## 6. The points economy

### 6.1 Currency

**EP (Elevar Points).** One currency, all games, server-authoritative.

### 6.2 Formula (v1, lives in `server/src/domain/scoring.ts`)

```
completion   = 10 EP                     (requires min duration + valid session)
outcome      = vsBot   : win  → 15 × {easy 1.0, medium 1.5, hard 2.2}
                        loss →  4
               local2P : 12 EP to the account holder, outcome-independent *
performance  = round(normalizedSkill × 15)
subtotal     = completion + outcome + performance
streakMult   = 1.0 / 1.1 / 1.2 / 1.3 / 1.5   at 1 / 3 / 7 / 14 / 30 day streaks
awarded      = floor(subtotal × streakMult × diminishing(nthMatchToday))

diminishing: matches 1–5 → ×1.0 · 6–10 → ×0.5 · 11+ → ×0.1
daily cap:   300 EP
```

\* **Why local 2-player pays flat:** only one of the two players is logged in. There is no
way to know which human held which paddle, so rewarding "the winner" is meaningless and
trivially farmed. Pay for participation instead, and let the *social* mode be about
bragging rights rather than EP. Cross-account competitive EP arrives with async
challenges in a later phase.

Two properties make this economy survivable:

1. **Diminishing returns + a daily cap** put a hard ceiling on what one account can mint
   per day. Your voucher liability per user per month is therefore *bounded and knowable*
   before you sign a single brand partnership.
2. **The formula is server-only and versioned** (`points_formula_version` on every match
   row). You can retune the economy without shipping an app update, and you can always
   explain historically why a given match paid what it paid.

The client shows an *estimate* with a subtle "syncing" state; the server's number is
truth and animates in on confirmation.

### 6.3 Ledger — the non-negotiable part

Points are never stored as a mutable field that gets `UPDATE`d. Every change is an
append-only row:

```
points_ledger(id, user_id, delta, balance_after, reason, ref_type, ref_id,
              idempotency_key UNIQUE, formula_version, created_at, meta jsonb)
```

`user_balances(user_id, points_balance, lifetime_points, version)` is a *cache* updated
in the **same transaction** with optimistic locking. If they ever disagree, the ledger
wins and the cache is rebuilt by replay. This is standard double-entry discipline and it
is the difference between "we can audit a redemption dispute" and "we cannot."

---

## 7. Data model (Postgres)

```sql
users            (id uuid pk, phone_e164 unique, display_name, avatar_id,
                  country, status, referral_code unique, referred_by, created_at)
devices          (id uuid pk, user_id fk, platform, app_version, fcm_token,
                  fingerprint, last_seen_at)
sessions         (id uuid pk, user_id fk, device_id fk, refresh_token_hash,
                  rotated_from, expires_at, revoked_at)

games            (id smallint pk, slug unique, title, is_active,
                  min_duration_ms, max_score, max_score_per_min)

match_sessions   (id uuid pk, user_id fk, game_id fk, mode, nonce unique,
                  seed bigint, issued_at, expires_at, status)      -- also mirrored in Redis
matches          (id uuid pk, user_id fk, game_id fk, mode, bot_difficulty,
                  started_at, ended_at, duration_ms,
                  p1_score, p2_score, outcome, normalized_skill,
                  raw_points, awarded_points, formula_version,
                  verification_state, replay_key, client_version,
                  idempotency_key unique, submitted_at)

points_ledger    (see §6.3)
user_balances    (user_id pk, points_balance, lifetime_points, version, updated_at)
daily_streaks    (user_id pk, current_streak, longest_streak, last_played_on)
cheat_flags      (id, user_id, match_id, rule, severity, created_at, resolved_at)

-- Phase 5 stubs, schema'd now so nothing has to be migrated later
rewards_catalog  (id, brand, title, cost_points, stock, window, active)
redemptions      (id, user_id, reward_id, cost_points, status,
                  voucher_ref_encrypted, created_at)
```

**Indexes that matter:** `matches(user_id, submitted_at desc)`,
`points_ledger(user_id, id desc)`, `matches(idempotency_key)` unique,
`match_sessions(nonce)` unique.

**Growth plan:** partition `matches` and `points_ledger` by month once past ~50M rows;
add a read replica for analytics before you add one for load.

---

## 8. API surface

```
POST   /v1/auth/otp/request      { phone }            → { requestId, resendAfter }
POST   /v1/auth/otp/verify       { requestId, code }  → { access, refresh, isNewUser }
POST   /v1/auth/refresh          { refresh }          → rotated pair
POST   /v1/auth/logout

GET    /v1/me                                         → profile, balance, streak
PATCH  /v1/me                    { displayName, avatarId }
DELETE /v1/me                                         → DPDP-compliant deletion

POST   /v1/matches/sessions      { gameId, mode, count? }  → [signed session tokens]
POST   /v1/matches               { GameResult + Idempotency-Key } → { awardedPoints, balance, breakdown }
GET    /v1/matches?cursor=

GET    /v1/leaderboard/:scope    global | weekly | game:<slug>  → top 100 + my rank
GET    /v1/points/ledger?cursor=

WS     /v1/stream                → balance.updated, leaderboard.changed, rank.changed
```

Fastify JSON Schemas generate the OpenAPI spec; the Flutter `api_client` package is
generated from it. **One source of truth for types across both languages** — worth the
setup on day one.

Every mutating request carries `Idempotency-Key`. Retries from the offline outbox are
therefore free and exactly-once.

---

## 9. Auth flow (phone OTP, India)

```
1. User enters phone (+91 default) → POST /auth/otp/request
2. Rate limits, layered:  3/phone/hour · 10/IP/hour · 30/device/day
3. 6-digit code, cryptographically random. Store bcrypt(code) in Redis, TTL 5 min.
   Never log or return the code.
4. MSG91 sends it via a DLT-registered template.
5. Verify: max 5 attempts, then the requestId is burned.
6. Success → user upserted by phone → access JWT (15 min) + refresh (30 d, rotating,
   one-time-use, reuse detection revokes the family).
7. New users → one-screen profile setup (display name + avatar). No email required.
```

**Android UX:** use the SMS Retriever API + an 11-char app hash in the template so the
code auto-fills with **zero SMS permissions**. Small effort, large conversion win.

**India setup work (start this in week 1 — it has a lead time):** DLT registration on a
telecom operator portal, entity + header (sender ID) + template approval. Typically 1–2
weeks. `Truecaller`/`OTPless` are a fallback if DLT drags.

**Cost:** ~₹0.15–0.25 per OTP via MSG91 vs ~₹0.45 via Twilio — a 3× difference that
matters at signup scale. Keep the provider behind an `OtpProvider` interface so
switching is a config change.

---

## 10. Offline-first sync

The whole app must work with the plane in flight mode.

**Session token pre-fetch.** Whenever online, the client tops up a local pool of ~5
signed match-session tokens (JWT, 24h expiry, carrying `userId, gameId, nonce, seed`).
Offline play consumes from the pool, so even a fully-offline match has a server-issued,
non-forgeable token attached. Empty pool + offline → the match still plays, but is
submitted as `unverified` and pays at a reduced rate. This is the design that makes
"offline gameplay, trusted scores" actually possible.

**Outbox.** Every finished match writes to a local drift `outbox` table with its
idempotency key *before* any network attempt. A background worker drains it on
connectivity regain with exponential backoff. UI shows pending EP in a muted state and
animates the confirmed value in when the server responds.

**Conflict rule:** the server is always right about points. The client never persists a
self-computed balance.

---

## 11. Anti-abuse

Because EP becomes vouchers, someone will try. Defence in depth, phased by how much the
points are actually worth:

| Layer | What it stops | Phase |
|---|---|---|
| **Session tokens** — no server-issued nonce, no points; nonce single-use | Naive replayed/forged POSTs | 2 |
| **Plausibility rules** — min duration, max score, max score/min, impossible combos (11–0 in 22s) | Scripted/tampered clients | 3 |
| **Rate + cap rules** — daily cap, diminishing returns, max matches/hour | Grinding and farm accounts | 3 |
| **Device & phone binding** — flag N accounts on one device fingerprint | Multi-accounting | 3 |
| **Behavioural flags** → `cheat_flags`, shadow-restrict from leaderboards rather than hard-ban | False-positive safety | 3 |
| **Replay verification** — Dart worker re-runs `game_core` on the submitted input log; mismatch ⇒ reject | Everything client-side | 5 |
| **Play Integrity API** attestation on redemption | Rooted/emulated devices | 5 |

Sequencing note: ship 2–3 for the beta. Replay verification is the strong lock, but it
only needs to exist the day points become redeemable — and it only exists at all because
§5.2 made the simulation deterministic.

Policy: **flag and withhold, don't ban.** Shadow-restricting a suspected farmer from
leaderboards and redemption is reversible; banning a false positive costs you a real user.

---

## 12. Realtime

Leaderboards live in Valkey sorted sets — `ZADD lb:global:2026-W34 <points> <userId>`,
read with `ZREVRANGE` + `ZREVRANK` for the user's own position. O(log n), never a
Postgres `ORDER BY … LIMIT` table scan. Postgres holds the durable ledger; Redis holds
the *ranking view*, rebuildable from it at any time.

A nightly BullMQ job snapshots each period into `leaderboard_snapshots` so history
survives a Redis flush.

The WS layer pushes only to subscribed rooms (`user:{id}`, `lb:global`), with the Redis
pub/sub adapter so any API instance can serve any socket. Client degrades to polling on
WS failure — realtime is an enhancement, never a dependency.

---

## 13. Compliance — flag now, resolve before Phase 5

**Not legal advice. Get Indian counsel before points become redeemable.**

- **Keep it a loyalty programme, not gaming-for-money.** No entry fee, no cash prizes, no
  wagering, no chance-based paid mechanics. Points are earned by play and redeemed for
  vouchers only. India's *Promotion and Regulation of Online Gaming Act, 2025* is
  aggressive toward online money games — the safe side of that line is wide, and this
  design should stay well inside it as long as money never flows *in* from players.
- **DPDP Act 2023:** phone numbers are personal data. Needs an explicit consent screen,
  a stated purpose, a privacy policy URL, and a working account-deletion flow
  (`DELETE /v1/me`) — which Google Play independently requires anyway.
- **Play Store:** loyalty rewards are fine; do not present anything as gambling. Data
  Safety form must match reality.
- **Voucher liability** is a real balance-sheet item once EP is redeemable. The daily cap
  in §6.2 is what keeps it bounded — model it before signing brand partners.

---

## 14. Roadmap

### Phase 0 — Foundations · ✅ done
Repo initialised, pub workspace scaffolded, palette sampled from the reference
artwork and fonts bundled. **Still outstanding: start DLT registration — it is
the long pole and nothing else blocks on it.** Terraform/DO provisioning moves
to Phase 2, where it is first needed.

### Phase 1 — Ping pong, playable, offline · ✅ built
`game_core` deterministic loop → `pingpong_sim` rules and physics → `game_pingpong`
Flame renderer and multi-touch → local 2P → bot with 3 measured difficulties →
juice pass (shake, particles, squash, haptics) → menu, mode select, result screen
with the points breakdown. 61 tests green, including golden determinism and
end-to-end replay verification through the real widget.

**Remaining before the exit criterion is met:** build the APK on Windows and play
it with real thumbs. Sound effects are not in yet — there is a seam for them in
`PingPongGame._reactTo`, but no audio assets exist.

### Phase 2 — Backend + identity · ~2 weeks
Fastify + Drizzle + migrations. OTP auth end-to-end with MSG91. `/matches` submission,
scoring formula, the ledger, `/me`. Flutter auth screens, secure token storage, outbox
sync. Deploy to staging.

### Phase 3 — The loop that retains · ~2 weeks
Leaderboards (Redis ZSETs + WS push), daily streaks, profile, match history, plausibility
rules + `cheat_flags`, admin panel (Retool or a minimal internal Fastify UI), Sentry,
push notifications. Play Store internal testing track → closed beta with ~50 real users.

### Phase 4 — Games 2–4 · ~3 weeks
Each new game only implements `ElevarGame` + a deterministic simulation. Nothing in
scoring, sync, or the hub changes. Budget ~1 week per game, faster as the shared layer
matures.

### Phase 5 — Rewards · ~3 weeks
Rewards catalogue, redemption flow with hold→confirm→settle ledger states, voucher
partner integration, the Dart replay-verification worker, Play Integrity, legal review,
public launch.

**~12 weeks to a public launch with 4 games and live redemption.**

---

## 15. Verification

- **`game_core`:** golden tests — given `(seed, inputLog)`, assert the exact final score.
  Run the same fixture on CI (Linux) and device to prove cross-platform determinism.
  This test is the foundation of Phase 5; it must exist from Phase 1.
- **Bot balance:** headless-simulate 1,000 matches per difficulty, assert human-proxy win
  rates land in target bands.
- **Ledger:** property test — for any random sequence of awards/redemptions/reversals,
  `sum(delta) == user_balances.points_balance`, always.
- **Idempotency:** submit the same match 50× concurrently, assert exactly one ledger row.
- **Offline:** airplane-mode a device, play 10 matches, reconnect, assert all 10 sync
  once with correct EP.
- **Anti-abuse:** a fixture suite of crafted malicious payloads that must all be rejected.
- **Load:** k6 against staging at 500 match-submits/sec; watch Postgres write IOPS.
- **Manual:** two people, one phone, one full match — the only test that tells you if it's fun.

---

## 16. Open questions

1. **Brand name** for the app — "Elevar Play" is a placeholder.
2. **Games 2–4:** any preferences? Good fits for the same one-device/vs-bot shape are
   air hockey, a reaction-time duel, a tap-race, or a 2-player quiz.
3. **Voucher partners:** own D2C brand only at first, or an aggregator?
4. **Team:** who's building? Solo vs. a team changes phase durations, not the plan.
5. **Guest play:** allow playing before login (better funnel), or gate on OTP (cleaner
   attribution)? Recommendation: allow guest play, prompt for OTP the moment they'd earn
   their first EP.

---

## Sources

- [The React Native game engine gap in 2026](https://dev.to/grzott/the-react-native-game-engine-gap-in-2026-rnge-skia-phaser-in-webview-expo-gl-55hp)
- [Flame engine](https://pub.dev/packages/flame) · [Collision detection](https://docs.flame-engine.org/latest/flame/collision_detection.html) · [Forge2D](https://docs.flame-engine.org/latest/bridge_packages/flame_forge2d/forge2d.html)
- [Flutter Casual Games Toolkit](https://flutter.dev/games)
- [Flutter state management 2026: Riverpod vs BLoC](https://asoasis.tech/articles/2026-04-17-2054-flutter-bloc-vs-riverpod-comparison-2026/)
- [Local-first Flutter with Riverpod + Drift](https://dinkomarinac.dev/blog/building-local-first-flutter-apps-with-riverpod-drift-and-powersync/)
- [DigitalOcean pricing](https://www.digitalocean.com/pricing) · [App Platform pricing](https://www.digitalocean.com/pricing/app-platform)
- [Best OTP service providers 2026](https://www.authgear.com/post/best-otp-service-providers/) · [Twilio Verify alternatives for India](https://www.messagecentral.com/blog/twilio-verify-alternative-india)
- [Firebase Authentication pricing 2026](https://blog.logto.io/firebase-authentication-pricing)
- [Server-side validation against cheaters](https://3e8.io/2016/slowdown-cheaters-with-server-side-validation/)
- [Supabase Realtime in production](https://www.agilesoftlabs.com/blog/2026/05/supabase-realtime-in-production-what)
