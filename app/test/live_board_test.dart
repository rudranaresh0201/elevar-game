import 'dart:async';

import 'package:elevar_play/data/leaderboard_client.dart';
import 'package:elevar_play/data/live_board.dart';
import 'package:elevar_play/data/player_profile.dart';
import 'package:elevar_play/data/points_repository.dart';
import 'package:elevar_play/data/profile_repository.dart';
import 'package:elevar_play/screens/leaderboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';

import 'support/fake_points_repository.dart';
import 'support/fake_profile_repository.dart';

/// A live board the test drives by hand: whatever it pushes into a tab's
/// controller arrives at the screen exactly as a realtime update would.
class FakeLiveBoard implements LiveBoard {
  final Map<String, StreamController<LeaderboardSnapshot>> channels =
      <String, StreamController<LeaderboardSnapshot>>{};
  final List<GameResult> recorded = <GameResult>[];
  final List<LeaderboardSubmission> synced = <LeaderboardSubmission>[];

  StreamController<LeaderboardSnapshot> channel(BoardTab tab) =>
      channels.putIfAbsent(tab.label, StreamController<LeaderboardSnapshot>.broadcast);

  @override
  bool get isConfigured => true;

  @override
  Stream<LeaderboardSnapshot> watch(BoardTab tab) => channel(tab).stream;

  @override
  Future<void> recordMatch(GameResult result) async => recorded.add(result);

  @override
  Future<void> syncPlayer(LeaderboardSubmission submission) async => synced.add(submission);
}

GameResult result(String slug, {int score = 10, GameMode mode = GameMode.vsBot, bool won = true}) =>
    GameResult(
      gameSlug: slug,
      mode: mode,
      botDifficulty: mode == GameMode.vsBot ? BotDifficulty.medium : null,
      durationMs: 1000,
      p1Score: score,
      p2Score: 5,
      outcome: won ? MatchOutcome.p1Win : MatchOutcome.p2Win,
      normalizedSkill: 0.5,
      seed: 1,
      tickCount: 120,
    );

void main() {
  group('ranking', () {
    test('rows are ranked by the tab metric, highest first, and you are marked', () {
      final snapshot = rankRows(
        <Map<String, dynamic>>[
          <String, dynamic>{'id': 'a', 'display_name': 'Asha', 'lifetime_points': 120, 'avatar_index': 1},
          <String, dynamic>{'id': 'b', 'display_name': 'Bo', 'lifetime_points': 900, 'avatar_index': 2},
          <String, dynamic>{'id': 'me', 'display_name': 'Rudra', 'lifetime_points': 450, 'avatar_index': 3},
          <String, dynamic>{'id': 'z', 'display_name': 'Zero', 'lifetime_points': 0},
        ],
        tab: BoardTab.overall,
        you: 'me',
      );
      expect(snapshot.rows.map((r) => r.displayName), <String>['Bo', 'Rudra', 'Asha']);
      expect(snapshot.rows.map((r) => r.rank), <int>[1, 2, 3]);
      expect(snapshot.yourRank, 2);
      expect(snapshot.rows[1].isYou, isTrue);
    });

    test('a game board reads its own metric and only its own game', () {
      const cricket = BoardTab(label: 'CRICKET', gameSlug: 'cricket', metric: BoardMetric.bestScore);
      final snapshot = rankRows(
        <Map<String, dynamic>>[
          <String, dynamic>{'player_id': 'a', 'game_slug': 'cricket', 'best_score': 34, 'wins': 9},
          <String, dynamic>{'player_id': 'b', 'game_slug': 'cricket', 'best_score': 61, 'wins': 1},
          <String, dynamic>{'player_id': 'c', 'game_slug': 'football', 'best_score': 99, 'wins': 50},
        ],
        tab: cricket,
        you: null,
      );
      expect(snapshot.rows.map((r) => r.playerId), <String>['b', 'a']);
      expect(snapshot.rows.first.points, 61);
    });

    test('scores count for high-score games, wins only against the bot', () {
      expect(BoardTab.contribution(result('fruit_drop', score: 820)).score, 820);
      expect(BoardTab.contribution(result('football', score: 4)).score, 0);
      expect(BoardTab.contribution(result('football')).won, isTrue);
      expect(BoardTab.contribution(result('football', mode: GameMode.local2P)).won, isFalse);
    });
  });

  group('screen', () {
    setUp(() {
      pointsRepository = FakePointsRepository(balanceValue: 300, pending: 0);
      profileRepository = FakeProfileRepository();
    });

    testWidgets('the board repaints when a live update arrives, and tabs switch boards',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final live = FakeLiveBoard();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: LeaderboardScreen(live: live))));
      await tester.pump();
      await tester.pump();

      LeaderboardSnapshot board(List<(String, int)> people) => LeaderboardSnapshot(
            rows: <LeaderboardRow>[
              for (var i = 0; i < people.length; i++)
                LeaderboardRow(
                  rank: i + 1,
                  playerId: people[i].$1,
                  displayName: people[i].$1,
                  points: people[i].$2,
                  avatarIndex: 0,
                ),
            ],
            yourRank: null,
            fetchedAt: DateTime.now(),
          );

      live.channel(BoardTab.overall).add(board(<(String, int)>[('Asha', 500), ('Bo', 400)]));
      await tester.pump();
      expect(find.text('Asha'), findsOneWidget);
      expect(find.textContaining('LIVE'), findsOneWidget);

      // Someone overtakes: no refresh, it just arrives.
      live.channel(BoardTab.overall).add(board(<(String, int)>[('Bo', 700), ('Asha', 500)]));
      await tester.pump();
      final bo = tester.getTopLeft(find.text('Bo'));
      final asha = tester.getTopLeft(find.text('Asha'));
      expect(bo.dy, lessThan(asha.dy), reason: 'the new leader should be on top');

      // The tab strip scrolls sideways; later tabs start off screen.
      await tester.ensureVisible(find.text('CRICKET'));
      await tester.pump();
      await tester.tap(find.text('CRICKET'));
      await tester.pump();
      expect(find.text('Best single game.'), findsOneWidget);
      final cricket = BoardTab.all.firstWhere((t) => t.gameSlug == 'cricket');
      live.channel(cricket).add(board(<(String, int)>[('Kiran', 61)]));
      await tester.pump();
      expect(find.text('Kiran'), findsOneWidget);
      expect(find.text('RUNS'), findsOneWidget);
    });
  });

  test('a finished match syncs totals then records the match', () async {
    final live = FakeLiveBoard();
    liveBoard = live;
    addTearDown(() => liveBoard = const DisabledLiveBoard());
    final profile = PlayerProfile(
      playerId: 'dev',
      displayName: 'Rudra',
      avatarIndex: 1,
      createdAt: DateTime(2026),
    );
    await syncAfterMatch(
      result('cricket', score: 42),
      () async => LeaderboardSubmission(
        profile: profile,
        lifetimePoints: 90,
        balance: 90,
        streakDays: 1,
        matchesPlayed: 3,
      ),
    );
    expect(live.synced.single.lifetimePoints, 90);
    expect(live.recorded.single.p1Score, 42);
  });
}
