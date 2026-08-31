import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:game_core/game_core.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../scoring/points_estimate.dart';

/// What today has paid out so far, and how long the streak is.
typedef TodaySoFar = ({int matches, int points, int streakDays});

/// One game's lifetime record.
typedef GameStat = ({
  String slug,
  int played,
  int won,
  int points,
  double bestSkill,
});

/// One row of the points ledger.
typedef LedgerEntry = ({
  int delta,
  int balanceAfter,
  String reason,
  String? refId,
  DateTime at,
});

/// The device's points ledger.
///
/// **Points are never a mutable counter.** Every change is an append-only row
/// in `points_ledger`, and `user_balance` is a cache updated inside the same
/// transaction. If they ever disagree the ledger wins and the cache is rebuilt
/// by replaying it. That is ordinary double-entry discipline, and it is the
/// difference between being able to audit a redemption dispute and not — which
/// matters from the first day points buy anything.
///
/// ## Why hand-written SQL and not an ORM
///
/// `docs/PLAN.md` §2.1 names drift, and drift is the right answer for a large
/// relational surface. This is four tables that must mirror the server's
/// Postgres schema exactly, and here the SQL below *is* the specification of
/// that schema — the Phase 2 port is a transliteration rather than a
/// re-derivation from generated Dart. It also keeps `build_runner` out of the
/// build entirely. If the local query surface grows past a handful of
/// statements, moving to drift is a mechanical change and nothing above this
/// file needs to know.
abstract class PointsRepository {
  Future<TodaySoFar> todaySoFar();

  /// Records a finished match and returns the new balance.
  ///
  /// Everything — the match row, the ledger row, the balance cache, the streak
  /// and the sync outbox entry — lands in one transaction, so a crash halfway
  /// through cannot leave points banked but unsynced or a match recorded twice.
  Future<int> recordMatch({
    required GameResult result,
    required PointsEstimate estimate,
    required List<int> replay,
  });

  Future<int> balance();

  /// Every point ever earned, before anything was spent.
  ///
  /// Separate from [balance] because the leaderboard ranks on this one:
  /// spending points on a voucher must not cost a player their place on the
  /// board, or the rewards shop and the leaderboard are in direct competition
  /// and the player has to pick one.
  Future<int> lifetimePoints();

  Future<List<GameStat>> perGameStats();

  Future<List<LedgerEntry>> recentLedger({int limit = 30});

  /// Matches banked locally but not yet accepted by the server.
  Future<int> pendingSyncCount();

  /// Wipes everything. Only for tests and a debug menu.
  Future<void> reset();

  /// Releases the database handle. The app never needs this — the ledger lives
  /// as long as the process — but a test suite that opens one per case does.
  Future<void> close();
}

/// The live implementation, on the device's SQLite.
class SqlitePointsRepository implements PointsRepository {
  SqlitePointsRepository({this.databaseFactoryOverride, this.pathOverride});

  /// Injected by tests so the same SQL runs against an in-process database.
  final DatabaseFactory? databaseFactoryOverride;
  final String? pathOverride;

  static const int _formulaVersion = 1;
  static const int _schemaVersion = 1;

  Database? _database;

  Future<Database> get _db async {
    final existing = _database;
    if (existing != null) return existing;

    final factory = databaseFactoryOverride ?? databaseFactory;
    final path = pathOverride ??
        p.join(await factory.getDatabasesPath(), 'elevar_points.db');

    final opened = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _schemaVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _createSchema,
      ),
    );
    _database = opened;
    return opened;
  }

  /// The schema, written to mirror `docs/PLAN.md` §7 column for column so the
  /// server's Postgres migration can be read straight off it.
  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE matches (
        id                TEXT    PRIMARY KEY,
        game_slug         TEXT    NOT NULL,
        mode              TEXT    NOT NULL,
        bot_difficulty    TEXT,
        played_on         TEXT    NOT NULL,
        played_at         INTEGER NOT NULL,
        duration_ms       INTEGER NOT NULL,
        p1_score          INTEGER NOT NULL,
        p2_score          INTEGER NOT NULL,
        outcome           TEXT    NOT NULL,
        normalized_skill  REAL    NOT NULL,
        seed              INTEGER NOT NULL,
        tick_count        INTEGER NOT NULL,
        awarded_points    INTEGER NOT NULL,
        formula_version   INTEGER NOT NULL,
        idempotency_key   TEXT    NOT NULL UNIQUE
      )
    ''');
    // `played_on` is a local calendar date rather than a timestamp because the
    // daily cap and the streak are both things a player experiences in their
    // own timezone, not in UTC.
    await db.execute(
      'CREATE INDEX matches_by_day ON matches (played_on)',
    );
    await db.execute(
      'CREATE INDEX matches_by_game ON matches (game_slug)',
    );

    await db.execute('''
      CREATE TABLE points_ledger (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        delta            INTEGER NOT NULL,
        balance_after    INTEGER NOT NULL,
        reason           TEXT    NOT NULL,
        ref_type         TEXT,
        ref_id           TEXT,
        idempotency_key  TEXT    NOT NULL UNIQUE,
        formula_version  INTEGER NOT NULL,
        created_at       INTEGER NOT NULL,
        meta             TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE user_balance (
        id              INTEGER PRIMARY KEY CHECK (id = 1),
        points_balance  INTEGER NOT NULL,
        lifetime_points INTEGER NOT NULL,
        current_streak  INTEGER NOT NULL,
        longest_streak  INTEGER NOT NULL,
        last_played_on  TEXT,
        version         INTEGER NOT NULL
      )
    ''');
    await db.insert('user_balance', <String, Object?>{
      'id': 1,
      'points_balance': 0,
      'lifetime_points': 0,
      'current_streak': 0,
      'longest_streak': 0,
      'last_played_on': null,
      'version': 0,
    });

    // The offline outbox. A finished match is written here *before* any network
    // attempt, so a race played in flight mode is never lost and, because the
    // idempotency key travels with it, a retry is exactly-once rather than a
    // second payout.
    await db.execute('''
      CREATE TABLE outbox (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        idempotency_key  TEXT    NOT NULL UNIQUE,
        endpoint         TEXT    NOT NULL,
        payload          TEXT    NOT NULL,
        replay           BLOB,
        attempts         INTEGER NOT NULL DEFAULT 0,
        next_attempt_at  INTEGER NOT NULL DEFAULT 0,
        last_error       TEXT,
        created_at       INTEGER NOT NULL,
        state            TEXT    NOT NULL DEFAULT 'pending'
      )
    ''');
    await db.execute(
      "CREATE INDEX outbox_pending ON outbox (state, next_attempt_at)",
    );
  }

  @override
  Future<TodaySoFar> todaySoFar() async {
    final db = await _db;
    final today = _localDate(DateTime.now());

    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS matches, COALESCE(SUM(awarded_points), 0) AS points '
      'FROM matches WHERE played_on = ?',
      <Object?>[today],
    );
    final balance = await db.query('user_balance', where: 'id = 1');

    final streak = balance.isEmpty
        ? 0
        : _streakAsOf(
            stored: balance.first['current_streak']! as int,
            lastPlayedOn: balance.first['last_played_on'] as String?,
            today: today,
          );

    return (
      matches: (rows.first['matches']! as int),
      points: (rows.first['points']! as int),
      streakDays: streak == 0 ? 1 : streak,
    );
  }

  @override
  Future<int> recordMatch({
    required GameResult result,
    required PointsEstimate estimate,
    required List<int> replay,
  }) async {
    final db = await _db;
    final now = DateTime.now();
    final today = _localDate(now);
    final key = _idempotencyKey(result, now);

    return db.transaction<int>((txn) async {
      final balanceRows = await txn.query('user_balance', where: 'id = 1');
      final current = balanceRows.first;
      final previousBalance = current['points_balance']! as int;
      final lifetime = current['lifetime_points']! as int;
      final storedStreak = current['current_streak']! as int;
      final longest = current['longest_streak']! as int;
      final lastPlayedOn = current['last_played_on'] as String?;

      final streak = _advanceStreak(
        stored: storedStreak,
        lastPlayedOn: lastPlayedOn,
        today: today,
      );
      final newBalance = previousBalance + estimate.awarded;

      final matchId = _randomId();

      await txn.insert('matches', <String, Object?>{
        'id': matchId,
        'game_slug': result.gameSlug,
        'mode': result.mode.wire,
        'bot_difficulty': result.botDifficulty?.wire,
        'played_on': today,
        'played_at': now.millisecondsSinceEpoch,
        'duration_ms': result.durationMs,
        'p1_score': result.p1Score,
        'p2_score': result.p2Score,
        'outcome': result.outcome.wire,
        'normalized_skill': result.normalizedSkill,
        'seed': result.seed,
        'tick_count': result.tickCount,
        'awarded_points': estimate.awarded,
        'formula_version': _formulaVersion,
        'idempotency_key': key,
      });

      // Even a zero payout gets a row. A day spent entirely against the cap
      // should be as auditable as a day that paid, and "why did this match
      // give me nothing" is a support question somebody will ask.
      await txn.insert('points_ledger', <String, Object?>{
        'delta': estimate.awarded,
        'balance_after': newBalance,
        'reason': 'match_reward',
        'ref_type': 'match',
        'ref_id': matchId,
        'idempotency_key': key,
        'formula_version': _formulaVersion,
        'created_at': now.millisecondsSinceEpoch,
        'meta': jsonEncode(<String, Object?>{
          'gameSlug': result.gameSlug,
          'completion': estimate.completion,
          'outcome': estimate.outcome,
          'performance': estimate.performance,
          'streakMultiplier': estimate.streakMultiplier,
          'diminishing': estimate.diminishing,
          'cappedByDailyLimit': estimate.cappedByDailyLimit,
        }),
      });

      await txn.update(
        'user_balance',
        <String, Object?>{
          'points_balance': newBalance,
          'lifetime_points': lifetime + estimate.awarded,
          'current_streak': streak,
          'longest_streak': streak > longest ? streak : longest,
          'last_played_on': today,
          'version': (current['version']! as int) + 1,
        },
        where: 'id = 1',
      );

      await txn.insert('outbox', <String, Object?>{
        'idempotency_key': key,
        'endpoint': 'POST /v1/matches',
        'payload': jsonEncode(result.toJson()),
        'replay': replay.isEmpty ? null : Uint8List.fromList(replay),
        'attempts': 0,
        'next_attempt_at': 0,
        'created_at': now.millisecondsSinceEpoch,
        'state': 'pending',
      });

      return newBalance;
    });
  }

  @override
  Future<int> balance() async {
    final db = await _db;
    final rows = await db.query('user_balance', where: 'id = 1');
    return rows.isEmpty ? 0 : rows.first['points_balance']! as int;
  }

  @override
  Future<int> lifetimePoints() async {
    final db = await _db;
    final rows = await db.query('user_balance', where: 'id = 1');
    return rows.isEmpty ? 0 : rows.first['lifetime_points']! as int;
  }

  @override
  Future<List<GameStat>> perGameStats() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT game_slug,
             COUNT(*)                              AS played,
             SUM(CASE WHEN outcome = 'p1Win' THEN 1 ELSE 0 END) AS won,
             COALESCE(SUM(awarded_points), 0)      AS points,
             COALESCE(MAX(normalized_skill), 0)    AS best_skill
      FROM matches
      GROUP BY game_slug
      ORDER BY played DESC
    ''');
    return rows
        .map((row) => (
              slug: row['game_slug']! as String,
              played: row['played']! as int,
              won: (row['won'] as int?) ?? 0,
              points: row['points']! as int,
              bestSkill: (row['best_skill']! as num).toDouble(),
            ))
        .toList();
  }

  @override
  Future<List<LedgerEntry>> recentLedger({int limit = 30}) async {
    final db = await _db;
    final rows = await db.query(
      'points_ledger',
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows
        .map((row) => (
              delta: row['delta']! as int,
              balanceAfter: row['balance_after']! as int,
              reason: row['reason']! as String,
              refId: row['ref_id'] as String?,
              at: DateTime.fromMillisecondsSinceEpoch(
                row['created_at']! as int,
              ),
            ))
        .toList();
  }

  @override
  Future<int> pendingSyncCount() async {
    final db = await _db;
    final rows = await db.rawQuery(
      "SELECT COUNT(*) AS n FROM outbox WHERE state = 'pending'",
    );
    return rows.first['n']! as int;
  }

  @override
  Future<void> reset() async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('matches');
      await txn.delete('points_ledger');
      await txn.delete('outbox');
      await txn.update(
        'user_balance',
        <String, Object?>{
          'points_balance': 0,
          'lifetime_points': 0,
          'current_streak': 0,
          'longest_streak': 0,
          'last_played_on': null,
          'version': 0,
        },
        where: 'id = 1',
      );
    });
  }

  @override
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  // --- streaks -------------------------------------------------------------

  /// The streak a match played today should count as.
  static int _advanceStreak({
    required int stored,
    required String? lastPlayedOn,
    required String today,
  }) {
    if (lastPlayedOn == null) return 1;
    if (lastPlayedOn == today) return stored == 0 ? 1 : stored;
    return lastPlayedOn == _yesterdayOf(today) ? stored + 1 : 1;
  }

  /// The streak as it stands *before* today's first match.
  ///
  /// A streak that was seven days long yesterday is still seven today, but one
  /// last touched a week ago is over — reading the stored number without this
  /// check would pay a lapsed player the multiplier they had when they left.
  static int _streakAsOf({
    required int stored,
    required String? lastPlayedOn,
    required String today,
  }) {
    if (lastPlayedOn == null) return 0;
    if (lastPlayedOn == today) return stored;
    if (lastPlayedOn == _yesterdayOf(today)) return stored;
    return 0;
  }

  static String _localDate(DateTime when) =>
      '${when.year.toString().padLeft(4, '0')}-'
      '${when.month.toString().padLeft(2, '0')}-'
      '${when.day.toString().padLeft(2, '0')}';

  static String _yesterdayOf(String date) {
    final parts = date.split('-').map(int.parse).toList();
    final day = DateTime(parts[0], parts[1], parts[2])
        .subtract(const Duration(days: 1));
    return _localDate(day);
  }

  // --- identity ------------------------------------------------------------

  static final Random _random = Random.secure();

  static String _randomId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// The key that makes a retry free.
  ///
  /// Derived from the match itself rather than drawn at random, so the same
  /// finished match can only ever mint points once however many times it is
  /// submitted — which is what the server's `Idempotency-Key` handling relies
  /// on.
  static String _idempotencyKey(GameResult result, DateTime at) =>
      '${result.gameSlug}:${result.seed}:${result.tickCount}:'
      '${result.p1Score}-${result.p2Score}:${at.millisecondsSinceEpoch}';
}

/// The instance the app uses. Swapped by tests.
PointsRepository pointsRepository = SqlitePointsRepository();
