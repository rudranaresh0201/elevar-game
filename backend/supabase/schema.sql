-- Elevar Play — realtime leaderboard.
--
-- Paste this whole file into Supabase → SQL Editor → New query → Run.
-- It is safe to run again: every statement is idempotent.
--
-- Shape:
--   players       one row per player: name, avatar, lifetime EP
--   game_records  one row per player per game: best score, wins, plays
--
-- Trust model, stated plainly: the phone reports its own numbers. Tables are
-- read-only to the app; the only way to write is the two functions below,
-- which run as the signed-in (anonymous) user, can only touch that user's own
-- rows, and refuse numbers that are obviously impossible. That stops casual
-- tampering. It does NOT stop a determined cheat with a modified APK — the
-- real defence is re-simulating the match replay on a server (docs/PLAN.md
-- §9) before anything on this board is exchanged for a voucher.

-- ---------------------------------------------------------------- tables ---

create table if not exists public.players (
  id              uuid primary key references auth.users (id) on delete cascade,
  device_id       text,
  display_name    text not null default 'Player',
  avatar_index    int  not null default 0,
  lifetime_points int  not null default 0 check (lifetime_points >= 0),
  matches_played  int  not null default 0 check (matches_played >= 0),
  streak_days     int  not null default 0 check (streak_days >= 0),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create table if not exists public.game_records (
  player_id     uuid not null references public.players (id) on delete cascade,
  game_slug     text not null,
  best_score    int  not null default 0,
  wins          int  not null default 0,
  plays         int  not null default 0,
  -- Copied from players so a per-game board is one query and one realtime
  -- channel, without a join the realtime stream cannot do.
  display_name  text not null default 'Player',
  avatar_index  int  not null default 0,
  updated_at    timestamptz not null default now(),
  primary key (player_id, game_slug)
);

create index if not exists players_by_points on public.players (lifetime_points desc);
create index if not exists records_by_score  on public.game_records (game_slug, best_score desc);
create index if not exists records_by_wins   on public.game_records (game_slug, wins desc);

-- ------------------------------------------------------------ row security --

alter table public.players      enable row level security;
alter table public.game_records enable row level security;

drop policy if exists "boards are public" on public.players;
create policy "boards are public" on public.players
  for select to anon, authenticated using (true);

drop policy if exists "boards are public" on public.game_records;
create policy "boards are public" on public.game_records
  for select to anon, authenticated using (true);

-- No insert/update/delete policies: the app cannot write to the tables
-- directly. Writes go through the functions below.

-- ---------------------------------------------------------------- writes ---

-- Updates the calling player's row with their current totals.
create or replace function public.sync_player(
  p_device_id       text,
  p_display_name    text,
  p_avatar_index    int,
  p_lifetime_points int,
  p_matches_played  int,
  p_streak_days     int
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  previous int;
  clean_name text := left(coalesce(nullif(btrim(p_display_name), ''), 'Player'), 18);
begin
  if me is null then
    raise exception 'not signed in';
  end if;

  select lifetime_points into previous from players where id = me;

  -- Lifetime EP never goes down, and cannot jump by more than a couple of
  -- days' daily cap in one sync (the app caps a day at 300).
  if previous is not null and p_lifetime_points < previous then
    p_lifetime_points := previous;
  end if;
  if previous is not null and p_lifetime_points - previous > 1000 then
    raise exception 'implausible points jump';
  end if;

  insert into players as p (id, device_id, display_name, avatar_index,
                            lifetime_points, matches_played, streak_days, updated_at)
  values (me, p_device_id, clean_name, greatest(p_avatar_index, 0),
          greatest(p_lifetime_points, 0), greatest(p_matches_played, 0),
          greatest(p_streak_days, 0), now())
  on conflict (id) do update set
    device_id       = excluded.device_id,
    display_name    = excluded.display_name,
    avatar_index    = excluded.avatar_index,
    lifetime_points = greatest(p.lifetime_points, excluded.lifetime_points),
    matches_played  = greatest(p.matches_played, excluded.matches_played),
    streak_days     = excluded.streak_days,
    updated_at      = now();

  -- Keep the copied name on the per-game rows current.
  update game_records
     set display_name = clean_name, avatar_index = greatest(p_avatar_index, 0)
   where player_id = me;
end;
$$;

-- Records one finished match for the calling player.
create or replace function public.record_match(
  p_game_slug text,
  p_score     int,
  p_won       boolean
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  who players%rowtype;
begin
  if me is null then
    raise exception 'not signed in';
  end if;
  if p_game_slug !~ '^[a-z_]{2,32}$' then
    raise exception 'bad game';
  end if;
  if p_score < 0 or p_score > 100000 then
    raise exception 'implausible score';
  end if;

  select * into who from players where id = me;
  if not found then
    raise exception 'sync_player first';
  end if;

  insert into game_records as r (player_id, game_slug, best_score, wins, plays,
                                 display_name, avatar_index, updated_at)
  values (me, p_game_slug, p_score, case when p_won then 1 else 0 end, 1,
          who.display_name, who.avatar_index, now())
  on conflict (player_id, game_slug) do update set
    best_score   = greatest(r.best_score, excluded.best_score),
    wins         = r.wins + excluded.wins,
    plays        = r.plays + 1,
    display_name = excluded.display_name,
    avatar_index = excluded.avatar_index,
    updated_at   = now();
end;
$$;

revoke all on function public.sync_player(text, text, int, int, int, int) from public;
revoke all on function public.record_match(text, int, boolean) from public;
grant execute on function public.sync_player(text, text, int, int, int, int) to authenticated;
grant execute on function public.record_match(text, int, boolean) to authenticated;

-- -------------------------------------------------------------- realtime ---

-- Broadcast row changes so open boards update live.
do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and tablename = 'players') then
    alter publication supabase_realtime add table public.players;
  end if;
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and tablename = 'game_records') then
    alter publication supabase_realtime add table public.game_records;
  end if;
end $$;
