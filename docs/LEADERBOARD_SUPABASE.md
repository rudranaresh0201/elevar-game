# The realtime leaderboard, on Supabase

The BOARD tab updates live: when anyone finishes a match, every open board
repaints within a second or so. Tabs: **Overall** (lifetime EP), **Fruit Drop**
and **Cricket** (best score), **Football**, **Shooting**, **Racing** and
**Ping Pong** (wins against the bot).

- `backend/supabase/schema.sql` — tables, security rules, the two write
  functions, realtime. Paste into the SQL editor and run.
- `app/lib/data/live_board.dart` — the board abstraction, ranking, what a match
  contributes to which board.
- `app/lib/data/supabase_board.dart` — the Supabase implementation.
- `app/lib/screens/leaderboard_screen.dart` — tabs and the live subscription.

## One-time setup

1. Supabase → **New project** (region: Mumbai).
2. **SQL Editor → New query**, paste `backend/supabase/schema.sql`, **Run**.
3. **Authentication → Sign In / Providers → Anonymous sign-ins: ON**. Players
   get a silent anonymous account; there is no sign-up screen.
4. **Project Settings → API**: copy the Project URL and the publishable (or
   legacy anon) key into `app/elevar.env.json` (copy the `.example` file). It is
   git-ignored.
5. Build with the keys:

   ```
   cd app
   flutter build apk --release --dart-define-from-file=elevar.env.json
   ```

Without the file the app builds and runs exactly as before, with the board
saying it is not connected.

## What syncs, and when

- **App start** and **profile edits**: name, avatar, lifetime EP, matches,
  streak (`sync_player`).
- **Every finished match**: the same totals, then the match itself
  (`record_match`): best score for Fruit Drop and Cricket, a win for vs-bot
  wins in the duel games, and a play for everything.
- Offline: the match still banks locally; totals are absolute, so the next
  sync corrects the overall board. Per-game plays and wins from a match that
  never reached the server are not replayed yet.

## Trust

The phone reports its own numbers. The tables are read-only to the app; the
two functions only ever touch the caller's own rows, never let lifetime EP go
down, and refuse jumps or scores that cannot happen. That stops casual
tampering, not a determined cheat with a modified APK. **Before ranks are
exchanged for vouchers**, a server should re-simulate each match from its
replay (the sims are built for exactly this — `docs/PLAN.md` §9) and only
verified matches should count.
