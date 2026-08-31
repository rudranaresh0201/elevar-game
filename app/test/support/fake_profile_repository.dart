import 'package:elevar_play/data/leaderboard_client.dart';
import 'package:elevar_play/data/player_profile.dart';
import 'package:elevar_play/data/profile_repository.dart';

/// An in-memory stand-in for widget tests.
///
/// Same reason as `FakePointsRepository`: a widget test process has no
/// platform channels, so the real SQLite-backed store cannot open a database
/// there. What the store actually does is covered against real SQL in
/// `profile_repository_test.dart`; this exists so screens have a name and an
/// avatar to render.
class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository({
    PlayerProfile? profile,
    this.board = LeaderboardSnapshot.empty,
  }) : _profile = profile ??
            PlayerProfile(
              playerId: 'test-player-000000',
              displayName: 'Test Player',
              avatarIndex: 0,
              createdAt: DateTime(2026),
            );

  PlayerProfile _profile;
  LeaderboardSnapshot board;

  @override
  Future<PlayerProfile> profile() async => _profile;

  @override
  Future<PlayerProfile> updateProfile({
    String? displayName,
    int? avatarIndex,
  }) async {
    _profile = _profile.copyWith(
      displayName: displayName,
      avatarIndex: avatarIndex,
    );
    return _profile;
  }

  @override
  Future<LeaderboardSnapshot> cachedBoard() async => board;

  @override
  Future<void> cacheBoard(LeaderboardSnapshot snapshot) async {
    board = snapshot;
  }

  @override
  Future<void> close() async {}
}

/// A client that returns whatever it was handed, or throws.
class FakeLeaderboardClient implements LeaderboardClient {
  FakeLeaderboardClient({this.board, this.failure});

  final LeaderboardSnapshot? board;
  final Object? failure;

  LeaderboardSubmission? lastSubmission;

  @override
  Future<LeaderboardSnapshot> submitAndFetch(
    LeaderboardSubmission submission,
  ) async {
    lastSubmission = submission;
    final thrown = failure;
    if (thrown != null) throw thrown;
    return board ?? LeaderboardSnapshot.empty;
  }
}
