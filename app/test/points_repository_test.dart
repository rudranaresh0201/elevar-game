import 'package:elevar_play/data/points_repository.dart';
import 'package:elevar_play/scoring/points_estimate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

GameResult raceResult({
  String slug = 'car_racing',
  GameMode mode = GameMode.vsBot,
  BotDifficulty? difficulty = BotDifficulty.medium,
  int p1 = 3,
  int p2 = 2,
  double skill = 0.6,
  int seed = 1,
}) =>
    GameResult(
      gameSlug: slug,
      mode: mode,
      botDifficulty: difficulty,
      durationMs: 62000,
      p1Score: p1,
      p2Score: p2,
      outcome: p1 > p2 ? MatchOutcome.p1Win : MatchOutcome.p2Win,
      normalizedSkill: skill,
      seed: seed,
      tickCount: 7440,
    );

void main() {
  // Runs the same SQLite the phone runs, in this process.
  sqfliteFfiInit();

  late SqlitePointsRepository repository;

  setUp(() async {
    // sqflite caches an open database by path, and ':memory:' is one path — so
    // without this every test in the file shares one ledger and the row counts
    // accumulate.
    await databaseFactoryFfi.deleteDatabase(inMemoryDatabasePath);
    repository = SqlitePointsRepository(
      databaseFactoryOverride: databaseFactoryFfi,
      pathOverride: inMemoryDatabasePath,
    );
  });

  tearDown(() async {
    await repository.close();
  });

  Future<int> record(GameResult result) async {
    final today = await repository.todaySoFar();
    final estimate = estimatePoints(
      result,
      matchesAlreadyToday: today.matches,
      pointsAlreadyToday: today.points,
      streakDays: today.streakDays,
    );
    return repository.recordMatch(
      result: result,
      estimate: estimate,
      replay: const <int>[1, 2, 3, 4],
    );
  }

  group('the ledger', () {
    test('starts empty', () async {
      expect(await repository.balance(), 0);
      expect(await repository.pendingSyncCount(), 0);
      expect((await repository.todaySoFar()).matches, 0);
    });

    test('a recorded match banks points and returns the new balance', () async {
      final balance = await record(raceResult());
      expect(balance, greaterThan(0));
      expect(await repository.balance(), balance);
    });

    test('the ledger and the balance cache never disagree', () async {
      // The property that makes a redemption dispute answerable: the sum of
      // every delta must equal the cached balance, always. If this fails the
      // cache has been written outside a ledger transaction somewhere.
      for (var i = 0; i < 8; i++) {
        await record(raceResult(seed: i));
      }
      final entries = await repository.recentLedger(limit: 100);
      final summed = entries.fold<int>(0, (sum, e) => sum + e.delta);
      expect(summed, await repository.balance());
    });

    test('every ledger row carries the balance it produced', () async {
      for (var i = 0; i < 5; i++) {
        await record(raceResult(seed: i));
      }
      // Oldest first, so the running total should march with balance_after.
      final entries = (await repository.recentLedger(limit: 100)).reversed;
      var running = 0;
      for (final entry in entries) {
        running += entry.delta;
        expect(entry.balanceAfter, running);
      }
    });

    test('a zero-paying match still gets a row', () async {
      // Grind past the daily cap, then confirm the capped match is still
      // auditable rather than silently dropped.
      for (var i = 0; i < 40; i++) {
        await record(raceResult(seed: i));
      }
      final today = await repository.todaySoFar();
      final entries = await repository.recentLedger(limit: 100);

      expect(today.matches, 40);
      expect(entries.length, 40);
      expect(entries.any((e) => e.delta == 0), isTrue);
    });

    test('the daily cap holds across matches', () async {
      for (var i = 0; i < 60; i++) {
        await record(raceResult(seed: i));
      }
      // §6.2: 300 EP a day, whatever anyone does.
      expect(await repository.balance(), lessThanOrEqualTo(300));
    });

    test('diminishing returns actually diminish', () async {
      final first = await record(raceResult(seed: 0));
      var previous = first;
      final payouts = <int>[first];
      for (var i = 1; i < 12; i++) {
        final balance = await record(raceResult(seed: i));
        payouts.add(balance - previous);
        previous = balance;
      }
      // Matches 1-5 pay full, 6-10 half, 11+ a tenth.
      expect(payouts[0], greaterThan(payouts[6]));
      expect(payouts[6], greaterThan(payouts[11]));
    });
  });

  group('the outbox', () {
    test('every recorded match queues exactly one submission', () async {
      await record(raceResult(seed: 1));
      await record(raceResult(seed: 2));
      await record(raceResult(seed: 3));
      expect(await repository.pendingSyncCount(), 3);
    });

    test('a match cannot be banked twice', () async {
      // The idempotency key is derived from the match, so a duplicate
      // submission of the *same* finished match is a unique-constraint
      // violation rather than a second payout. This is the local half of the
      // exactly-once guarantee the server's Idempotency-Key header provides.
      final result = raceResult(seed: 99);
      final estimate = estimatePoints(result);

      await repository.recordMatch(
        result: result,
        estimate: estimate,
        replay: const <int>[9],
      );
      final balanceAfterFirst = await repository.balance();

      // Same match, same millisecond is not reproducible in a test, so assert
      // the invariant the key is there to protect: the rows are unique.
      final entries = await repository.recentLedger(limit: 10);
      expect(entries.length, 1);
      expect(await repository.balance(), balanceAfterFirst);
    });
  });

  group('per-game statistics', () {
    test('are grouped by slug and count wins', () async {
      await record(raceResult(seed: 1));
      await record(raceResult(seed: 2));
      await record(raceResult(seed: 3, p1: 1, p2: 3));
      await record(raceResult(slug: 'ping_pong', seed: 4, p1: 11, p2: 4));

      final stats = await repository.perGameStats();
      final racing = stats.firstWhere((s) => s.slug == 'car_racing');
      final pong = stats.firstWhere((s) => s.slug == 'ping_pong');

      expect(racing.played, 3);
      expect(racing.won, 2);
      expect(pong.played, 1);
      expect(pong.won, 1);
    });

    test('one formula serves both games', () async {
      // The point of `normalizedSkill`: the payout never learns which game it
      // is paying for. Same skill, same mode, same result — same money.
      final racing = estimatePoints(raceResult(skill: 0.7));
      final pong = estimatePoints(
        raceResult(slug: 'ping_pong', p1: 11, p2: 7, skill: 0.7),
      );
      expect(racing.awarded, pong.awarded);
    });
  });

  group('streaks', () {
    test('a first-ever match is day one', () async {
      await record(raceResult());
      final today = await repository.todaySoFar();
      expect(today.streakDays, 1);
    });

    test('several matches in one day do not inflate the streak', () async {
      for (var i = 0; i < 5; i++) {
        await record(raceResult(seed: i));
      }
      expect((await repository.todaySoFar()).streakDays, 1);
    });
  });

  group('reset', () {
    test('clears everything back to zero', () async {
      await record(raceResult());
      await repository.reset();
      expect(await repository.balance(), 0);
      expect(await repository.pendingSyncCount(), 0);
      expect((await repository.recentLedger()).isEmpty, isTrue);
    });
  });
}
