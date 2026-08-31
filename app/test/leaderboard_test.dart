import 'package:elevar_play/data/leaderboard_client.dart';
import 'package:elevar_play/data/leaderboard_service.dart';
import 'package:elevar_play/data/player_profile.dart';
import 'package:elevar_play/data/points_repository.dart';
import 'package:elevar_play/data/profile_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_points_repository.dart';
import 'support/fake_profile_repository.dart';

void main() {
  group('reading a webhook response', () {
    // The board will be served by whatever Elevar already runs — most likely
    // an n8n webhook over a Google Sheet — and the exact shape of that
    // response is not worth an app release to agree on. These are the shapes
    // the parser has to survive; a new one showing up should be a test here
    // rather than a crash on a player's phone.
    test('reads {"top": [...], "you": {...}}', () {
      final board = WebhookLeaderboardClient.parseBoard(
        '''
        {
          "you": {"rank": 42},
          "top": [
            {"rank": 1, "playerId": "a", "displayName": "Aisha", "points": 900},
            {"rank": 2, "playerId": "me", "displayName": "You", "points": 800}
          ]
        }
        ''',
        you: 'me',
      );

      expect(board.rows, hasLength(2));
      expect(board.rows.first.displayName, 'Aisha');
      expect(board.yourRank, 42);
      expect(board.rows[1].isYou, isTrue);
      expect(board.rows.first.isYou, isFalse);
    });

    test('reads a bare array, deriving rank from the order', () {
      final board = WebhookLeaderboardClient.parseBoard(
        '[{"playerId":"a","name":"Rohit","points":120},'
        '{"playerId":"b","name":"Tanuja","points":90}]',
        you: 'nobody',
      );

      expect(board.rows.map((r) => r.rank), <int>[1, 2]);
      expect(board.rows.map((r) => r.displayName), <String>['Rohit', 'Tanuja']);
    });

    test('reads snake_case keys and numeric strings', () {
      // A sheet exports everything as text, so a points column arrives as
      // "1450" rather than 1450 more often than not.
      final board = WebhookLeaderboardClient.parseBoard(
        '{"rows":[{"player_id":"z","display_name":"Sam","points":"1450"}]}',
        you: 'z',
      );

      expect(board.rows.single.points, 1450);
      expect(board.rows.single.playerId, 'z');
      expect(board.rows.single.isYou, isTrue);
    });

    test('derives your rank from the rows when the server omits it', () {
      final board = WebhookLeaderboardClient.parseBoard(
        '[{"playerId":"a","points":9},{"playerId":"me","points":8}]',
        you: 'me',
      );
      expect(board.yourRank, 2);
    });

    test('a row missing everything still renders', () {
      final board =
          WebhookLeaderboardClient.parseBoard('[{}]', you: 'me');
      expect(board.rows.single.displayName, 'Player');
      expect(board.rows.single.points, 0);
      expect(board.rows.single.rank, 1);
    });

    test('anything that is not a board is refused, not guessed at', () {
      expect(
        () => WebhookLeaderboardClient.parseBoard('<html>502</html>', you: 'm'),
        throwsA(isA<LeaderboardUnavailable>()),
      );
      expect(
        () => WebhookLeaderboardClient.parseBoard('{"ok": true}', you: 'm'),
        throwsA(isA<LeaderboardUnavailable>()),
      );
    });
  });

  group('the service', () {
    late FakeProfileRepository profiles;

    setUp(() {
      profiles = FakeProfileRepository();
      pointsRepository = FakePointsRepository(balanceValue: 300);
      profileRepository = profiles;
    });

    test('reports notConfigured when no endpoint is compiled in', () async {
      // No --dart-define in a test run, so this is the real default state and
      // the one every developer sees. It must not read as an error.
      final result = await LeaderboardService(profiles: profiles).refresh();
      expect(result.status, BoardStatus.notConfigured);
      expect(result.error, isNull);
    });

    test('falls back to the cache and says so when the fetch fails', () async {
      profiles.board = LeaderboardSnapshot(
        rows: const <LeaderboardRow>[
          LeaderboardRow(
            rank: 1,
            playerId: 'a',
            displayName: 'Cached',
            points: 10,
            avatarIndex: 0,
          ),
        ],
        yourRank: 7,
        fetchedAt: DateTime(2026, 8, 30),
      );

      final service = LeaderboardService(
        client: FakeLeaderboardClient(
          failure: const LeaderboardUnavailable('boom'),
        ),
        profiles: profiles,
        configured: true,
      );

      final result = await service.refresh();
      expect(result.status, BoardStatus.stale);
      expect(result.snapshot.rows.single.displayName, 'Cached');
      expect(result.error, 'boom');
    });

    test('caches a board it managed to fetch', () async {
      final client = FakeLeaderboardClient(
        board: LeaderboardSnapshot(
          rows: const <LeaderboardRow>[
            LeaderboardRow(
              rank: 1,
              playerId: 'test-player-000000',
              displayName: 'Test Player',
              points: 500,
              avatarIndex: 0,
            ),
          ],
          yourRank: 1,
          fetchedAt: DateTime(2026, 8, 31),
        ),
      );

      final result = await LeaderboardService(
        client: client,
        profiles: profiles,
        configured: true,
      ).refresh();

      expect(result.status, BoardStatus.live);
      expect(profiles.board.rows, hasLength(1));
      // The submission carries lifetime points, not the spendable balance:
      // buying a voucher must not cost a player their place on the board.
      expect(client.lastSubmission!.lifetimePoints, 300);
      expect(client.lastSubmission!.profile.playerId, 'test-player-000000');
    });
  });

  group('the profile store', () {
    sqfliteFfiInit();

    late SqliteProfileRepository repository;

    setUp(() async {
      // sqflite caches an open database by path, and ':memory:' is one path —
      // so without this every test in the group shares one profile.
      await databaseFactoryFfi.deleteDatabase(inMemoryDatabasePath);
      repository = SqliteProfileRepository(
        databaseFactoryOverride: databaseFactoryFfi,
        pathOverride: inMemoryDatabasePath,
      );
    });

    tearDown(() => repository.close());

    test('creates a profile once and never regenerates the id', () async {
      final first = await repository.profile();
      final second = await repository.profile();

      expect(first.playerId, second.playerId);
      expect(first.playerId, hasLength(32));
      expect(first.hasDefaultName, isTrue);
    });

    test('a chosen name survives, and the id does not change with it',
        () async {
      final before = await repository.profile();
      final after = await repository.updateProfile(displayName: '  Rudra  ');

      expect(after.displayName, 'Rudra');
      expect(after.playerId, before.playerId);
      expect((await repository.profile()).displayName, 'Rudra');
      expect(after.hasDefaultName, isFalse);
    });

    test('a name that is too long is cut, not rejected', () async {
      final after = await repository.updateProfile(
        displayName: 'A' * 60,
      );
      // This string is rendered in a fixed-width row on a 320pt phone and
      // posted to somebody else's webhook. Neither wants an unbounded one.
      expect(after.displayName.length, 18);
    });

    test('an empty name keeps the one already there', () async {
      await repository.updateProfile(displayName: 'Keeper');
      final after = await repository.updateProfile(displayName: '   ');
      expect(after.displayName, 'Keeper');
    });

    test('the cached board round-trips and comes back marked stale', () async {
      final me = await repository.profile();
      await repository.cacheBoard(
        LeaderboardSnapshot(
          rows: <LeaderboardRow>[
            LeaderboardRow(
              rank: 1,
              playerId: me.playerId,
              displayName: 'Me',
              points: 40,
              avatarIndex: 2,
            ),
            const LeaderboardRow(
              rank: 2,
              playerId: 'other',
              displayName: 'Them',
              points: 30,
              avatarIndex: 3,
            ),
          ],
          yourRank: 1,
          fetchedAt: DateTime(2026, 8, 31, 12),
        ),
      );

      final cached = await repository.cachedBoard();
      expect(cached.rows, hasLength(2));
      expect(cached.yourRank, 1);
      expect(cached.stale, isTrue);
      // Recomputed against this device's id rather than trusted from storage,
      // so the highlight is right even if the cache predates a change.
      expect(cached.rows.first.isYou, isTrue);
      expect(cached.rows.last.isYou, isFalse);
    });

    test('an empty cache is empty, not an exception', () async {
      expect((await repository.cachedBoard()).isEmpty, isTrue);
    });
  });
}
