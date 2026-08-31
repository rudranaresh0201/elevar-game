import 'package:elevar_play/data/points_repository.dart';
import 'package:elevar_play/scoring/points_estimate.dart';
import 'package:game_core/game_core.dart';

/// An in-memory stand-in for widget tests.
///
/// Widget tests run in a process with no platform channels, so the real
/// SQLite-backed repository cannot open a database there. The *ledger's own*
/// behaviour is covered against real SQL in `points_repository_test.dart`;
/// this exists purely so screens have something to read.
class FakePointsRepository implements PointsRepository {
  FakePointsRepository({
    this.balanceValue = 0,
    this.matchesToday = 0,
    this.pointsToday = 0,
    this.streakDays = 1,
    this.pending = 0,
    this.stats = const <GameStat>[],
  });

  int balanceValue;

  /// Defaults to the balance, which is true until something is spent.
  int? lifetimeOverride;
  int get lifetimeValue => lifetimeOverride ?? balanceValue;

  int matchesToday;
  int pointsToday;
  int streakDays;
  int pending;
  List<GameStat> stats;

  final List<GameResult> recorded = <GameResult>[];

  @override
  Future<int> balance() async => balanceValue;

  @override
  Future<int> lifetimePoints() async => lifetimeValue;

  @override
  Future<List<GameStat>> perGameStats() async => stats;

  @override
  Future<int> pendingSyncCount() async => pending;

  @override
  Future<List<LedgerEntry>> recentLedger({int limit = 30}) async =>
      const <LedgerEntry>[];

  @override
  Future<TodaySoFar> todaySoFar() async =>
      (matches: matchesToday, points: pointsToday, streakDays: streakDays);

  @override
  Future<int> recordMatch({
    required GameResult result,
    required PointsEstimate estimate,
    required List<int> replay,
  }) async {
    recorded.add(result);
    balanceValue += estimate.awarded;
    matchesToday++;
    pointsToday += estimate.awarded;
    return balanceValue;
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> reset() async {
    balanceValue = 0;
    matchesToday = 0;
    pointsToday = 0;
    pending = 0;
    recorded.clear();
  }
}
