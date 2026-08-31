import 'dart:convert';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'leaderboard_client.dart';
import 'player_profile.dart';
import 'points_repository.dart';

/// The player's identity, and the last board they were shown.
///
/// ## Why this is a second database
///
/// It would have been one line shorter to add two tables to
/// `points_repository.dart`. It is deliberately not there, and the line that
/// separates them is worth stating: **the ledger is a record and this is a
/// cache.** Every row in `points_ledger` is auditable, append-only and has to
/// survive a redemption dispute; every row here can be deleted at any moment
/// and refetched with nothing lost but a network round trip. Keeping a cache
/// inside a book of record means every future schema change to the cache is a
/// migration against money.
///
/// The one thing that is *not* disposable is the player id, which is why it
/// gets a row of its own and is never rewritten.
abstract class ProfileRepository {
  /// The profile, creating one on first run.
  Future<PlayerProfile> profile();

  Future<PlayerProfile> updateProfile({String? displayName, int? avatarIndex});

  /// The last board that was successfully fetched, or empty.
  Future<LeaderboardSnapshot> cachedBoard();

  Future<void> cacheBoard(LeaderboardSnapshot snapshot);

  Future<void> close();
}

/// The live implementation.
class SqliteProfileRepository implements ProfileRepository {
  SqliteProfileRepository({this.databaseFactoryOverride, this.pathOverride});

  final DatabaseFactory? databaseFactoryOverride;
  final String? pathOverride;

  static const int _schemaVersion = 1;

  Database? _database;

  Future<Database> get _db async {
    final existing = _database;
    if (existing != null) return existing;

    final factory = databaseFactoryOverride ?? databaseFactory;
    final path = pathOverride ??
        p.join(await factory.getDatabasesPath(), 'elevar_social.db');

    final opened = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _schemaVersion,
        onCreate: _createSchema,
      ),
    );
    _database = opened;
    return opened;
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE player_profile (
        id            INTEGER PRIMARY KEY CHECK (id = 1),
        player_id     TEXT    NOT NULL,
        display_name  TEXT    NOT NULL,
        avatar_index  INTEGER NOT NULL,
        created_at    INTEGER NOT NULL
      )
    ''');

    // One row, holding the whole board as JSON.
    //
    // A table with a row per player would be the tidy answer and would buy
    // nothing: the board is never queried, filtered or joined — it is fetched
    // whole, shown whole, and replaced whole. Storing it as one document means
    // a server that adds a field tomorrow does not need a migration here.
    await db.execute('''
      CREATE TABLE leaderboard_cache (
        id          INTEGER PRIMARY KEY CHECK (id = 1),
        payload     TEXT    NOT NULL,
        your_rank   INTEGER,
        fetched_at  INTEGER NOT NULL
      )
    ''');
  }

  @override
  Future<PlayerProfile> profile() async {
    final db = await _db;
    final rows = await db.query('player_profile', where: 'id = 1');
    if (rows.isNotEmpty) return _readProfile(rows.first);

    final created = PlayerProfile(
      playerId: _randomId(),
      displayName: _generatedName(),
      avatarIndex: _random.nextInt(PlayerAvatars.all.length),
      createdAt: DateTime.now(),
    );
    await db.insert('player_profile', <String, Object?>{
      'id': 1,
      'player_id': created.playerId,
      'display_name': created.displayName,
      'avatar_index': created.avatarIndex,
      'created_at': created.createdAt.millisecondsSinceEpoch,
    });
    return created;
  }

  @override
  Future<PlayerProfile> updateProfile({
    String? displayName,
    int? avatarIndex,
  }) async {
    final current = await profile();
    final name = _sanitiseName(displayName) ?? current.displayName;
    final avatar = avatarIndex ?? current.avatarIndex;

    final db = await _db;
    await db.update(
      'player_profile',
      <String, Object?>{
        'display_name': name,
        'avatar_index': avatar % PlayerAvatars.all.length,
      },
      where: 'id = 1',
    );
    return current.copyWith(displayName: name, avatarIndex: avatar);
  }

  @override
  Future<LeaderboardSnapshot> cachedBoard() async {
    final db = await _db;
    final rows = await db.query('leaderboard_cache', where: 'id = 1');
    if (rows.isEmpty) return LeaderboardSnapshot.empty;

    final row = rows.first;
    final me = (await profile()).playerId;
    try {
      final decoded = jsonDecode(row['payload']! as String);
      if (decoded is! List) return LeaderboardSnapshot.empty;
      final parsed = <LeaderboardRow>[];
      for (var i = 0; i < decoded.length; i++) {
        final entry = decoded[i];
        if (entry is! Map<String, Object?>) continue;
        final board = LeaderboardRow.fromJson(entry, i + 1);
        parsed.add(board.markedAsYou(board.playerId == me));
      }
      return LeaderboardSnapshot(
        rows: parsed,
        yourRank: row['your_rank'] as int?,
        fetchedAt:
            DateTime.fromMillisecondsSinceEpoch(row['fetched_at']! as int),
        stale: true,
      );
    } on FormatException {
      // A cache that cannot be read is a cache that does not exist. Never a
      // crash on a screen the player opened to see a number.
      return LeaderboardSnapshot.empty;
    }
  }

  @override
  Future<void> cacheBoard(LeaderboardSnapshot snapshot) async {
    final db = await _db;
    await db.insert(
      'leaderboard_cache',
      <String, Object?>{
        'id': 1,
        'payload': jsonEncode(
          <Map<String, Object?>>[
            for (final row in snapshot.rows) row.toJson(),
          ],
        ),
        'your_rank': snapshot.yourRank,
        'fetched_at': (snapshot.fetchedAt ?? DateTime.now())
            .millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  static PlayerProfile _readProfile(Map<String, Object?> row) => PlayerProfile(
        playerId: row['player_id']! as String,
        displayName: row['display_name']! as String,
        avatarIndex: row['avatar_index']! as int,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
      );

  static final Random _random = Random.secure();

  static String _randomId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _generatedName() =>
      '${PlayerProfile.defaultNamePrefix}${1000 + _random.nextInt(9000)}';

  /// Trims, caps and rejects an empty name.
  ///
  /// The cap is not cosmetic — this string is rendered in a fixed-width row on
  /// a 320pt phone and posted to somebody else's webhook, and neither of those
  /// wants an unbounded one.
  static String? _sanitiseName(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.isEmpty) return null;
    return trimmed.length <= 18 ? trimmed : trimmed.substring(0, 18);
  }
}

/// Reads everything the board needs about this player, from both stores.
///
/// It lives here rather than on a screen because two screens need it — the
/// leaderboard and the profile tab — and neither should have to know that the
/// numbers come from one database and the name from another.
Future<LeaderboardSubmission> buildSubmission({
  ProfileRepository? profiles,
  PointsRepository? points,
}) async {
  final profileStore = profiles ?? profileRepository;
  final pointsStore = points ?? pointsRepository;

  final profile = await profileStore.profile();
  final today = await pointsStore.todaySoFar();
  final stats = await pointsStore.perGameStats();

  return LeaderboardSubmission(
    profile: profile,
    lifetimePoints: await pointsStore.lifetimePoints(),
    balance: await pointsStore.balance(),
    streakDays: today.streakDays,
    matchesPlayed: stats.fold<int>(0, (sum, stat) => sum + stat.played),
  );
}

/// The instance the app uses. Swapped by tests, and by the web bootstrap.
ProfileRepository profileRepository = SqliteProfileRepository();
