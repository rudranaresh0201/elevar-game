import 'package:elevar_play/data/points_repository.dart';
import 'package:elevar_play/main.dart';
import 'package:elevar_play/scoring/points_estimate.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';

import 'package:elevar_play/games/registry.dart';

import 'package:elevar_play/data/profile_repository.dart';

import 'support/fake_points_repository.dart';
import 'support/fake_profile_repository.dart';

GameResult result({
  required GameMode mode,
  BotDifficulty? difficulty,
  int p1 = 11,
  int p2 = 5,
  double skill = 0.6,
}) =>
    GameResult(
      gameSlug: 'ping_pong',
      mode: mode,
      botDifficulty: difficulty,
      durationMs: 90000,
      p1Score: p1,
      p2Score: p2,
      outcome: p1 > p2 ? MatchOutcome.p1Win : MatchOutcome.p2Win,
      normalizedSkill: skill,
      seed: 1,
      tickCount: 10800,
    );

/// Pumps the app on a portrait phone viewport.
///
/// The default 800x600 test surface is landscape, and this game is portrait-
/// only by design — on the default surface the game grid sits below the fold
/// and taps land on nothing.
Future<void> pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const ElevarPlayApp());
  await tester.pumpAndSettle();
}


/// Scrolls a hub tile into view, then taps it.
///
/// The grid sits below the balance card and the featured tile, so on every
/// phone size at least one game is off screen when the hub opens. `tap` on an
/// off-screen widget does not scroll to it — it taps empty space — so this is
/// the difference between a test that navigates and one that silently does
/// nothing and then fails on the next line.
Future<void> openGame(WidgetTester tester, String title) async {
  final tile = find.text(title);
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

void main() {
  group('app shell', () {
    setUp(() {
      // The hub reads the ledger on build, and a widget test process has no
      // platform channels for SQLite to open a database over.
      pointsRepository = FakePointsRepository(balanceValue: 140, pending: 2);
      profileRepository = FakeProfileRepository();
    });

    testWidgets('opens on the hub with ping pong playable', (tester) async {
      await pumpApp(tester);

      expect(find.text('ELEVAR'), findsOneWidget);
      expect(find.text('Test Player'), findsOneWidget);
      expect(find.text('PING\nPONG'), findsOneWidget);
      expect(find.text('CAR\nRACING'), findsOneWidget);
      // Balance and unsynced count both come off the ledger.
      expect(find.text('140'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('every registry game gets a tile', (tester) async {
      await pumpApp(tester);
      for (final game in elevarGames) {
        // The featured tile sets its title on one line; grid tiles keep the
        // line break.
        final onOneLine = game.title.replaceAll('\n', ' ');
        final found = find.text(game.title).evaluate().length +
            (onOneLine == game.title ? 0 : find.text(onOneLine).evaluate().length);
        expect(found, 1, reason: '${game.slug} has no tile');
      }
    });

    testWidgets('reaches the racing mode select and can pick a circuit',
        (tester) async {
      await pumpApp(tester);

      await openGame(tester, 'CAR\nRACING');

      expect(find.text('CAR RACING'), findsOneWidget);
      expect(find.text('START RACE'), findsOneWidget);

      await tester.tap(find.text('SUNSET LOOP'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Wider and faster'), findsOneWidget);
    });

    testWidgets('racing two-player mode hides bot difficulty', (tester) async {
      await pumpApp(tester);
      await openGame(tester, 'CAR\nRACING');

      await tester.tap(find.text('2 PLAYERS'));
      await tester.pumpAndSettle();

      expect(find.text('DIFFICULTY'), findsNothing);
      expect(find.textContaining('Sit facing each other'), findsOneWidget);
    });

    testWidgets('rewards screen shows the catalogue against the balance',
        (tester) async {
      await pumpApp(tester);

      await tester.tap(find.text('SPEND EP'));
      await tester.pumpAndSettle();

      expect(find.text('REWARDS'), findsOneWidget);
      expect(find.text('FREE SHIPPING'), findsOneWidget);
      // The 300 EP reward, against the fake's 140 EP balance.
      expect(find.text('160 EP to go'), findsOneWidget);
      expect(find.text('SOON'), findsWidgets);
    });

    testWidgets('reaches mode select and can pick a bot difficulty',
        (tester) async {
      await pumpApp(tester);

      await openGame(tester, 'PING\nPONG');

      expect(find.text('PING PONG'), findsOneWidget);
      expect(find.text('VS BOT'), findsOneWidget);
      expect(find.text('START MATCH'), findsOneWidget);

      await tester.tap(find.text('HARD'));
      await tester.pumpAndSettle();
      expect(find.text('Reads everything. Rarely misses.'), findsOneWidget);
    });

    testWidgets('two-player mode hides bot difficulty', (tester) async {
      await pumpApp(tester);
      await openGame(tester, 'PING\nPONG');

      await tester.tap(find.text('2 PLAYERS'));
      await tester.pumpAndSettle();

      expect(find.text('DIFFICULTY'), findsNothing);
      expect(find.textContaining('Sit facing each other'), findsOneWidget);
    });
  });

  group('points estimate', () {
    test('a hard win pays more than an easy one', () {
      final easy = estimatePoints(
        result(mode: GameMode.vsBot, difficulty: BotDifficulty.easy),
      );
      final hard = estimatePoints(
        result(mode: GameMode.vsBot, difficulty: BotDifficulty.hard),
      );
      expect(hard.awarded, greaterThan(easy.awarded));
    });

    test('losing still pays something, so a bad match is not wasted', () {
      final lost = estimatePoints(
        result(
          mode: GameMode.vsBot,
          difficulty: BotDifficulty.medium,
          p1: 4,
          p2: 11,
        ),
      );
      expect(lost.awarded, greaterThan(0));
    });

    test('shared-screen play pays a flat rate regardless of who won', () {
      final redWon = estimatePoints(result(mode: GameMode.local2P, p1: 11, p2: 3));
      final blueWon =
          estimatePoints(result(mode: GameMode.local2P, p1: 3, p2: 11));
      expect(redWon.outcome, blueWon.outcome);
    });

    test('grinding hits diminishing returns', () {
      final first = estimatePoints(
        result(mode: GameMode.vsBot, difficulty: BotDifficulty.medium),
      );
      final eleventh = estimatePoints(
        result(mode: GameMode.vsBot, difficulty: BotDifficulty.medium),
        matchesAlreadyToday: 12,
      );
      expect(eleventh.awarded, lessThan(first.awarded ~/ 2));
    });

    test('the daily cap is a hard ceiling', () {
      final capped = estimatePoints(
        result(mode: GameMode.vsBot, difficulty: BotDifficulty.hard),
        pointsAlreadyToday: 299,
      );
      expect(capped.awarded, lessThanOrEqualTo(1));
      expect(capped.cappedByDailyLimit, isTrue);
    });

    test('a streak multiplies the payout', () {
      final plain = estimatePoints(
        result(mode: GameMode.vsBot, difficulty: BotDifficulty.medium),
      );
      final streaked = estimatePoints(
        result(mode: GameMode.vsBot, difficulty: BotDifficulty.medium),
        streakDays: 30,
      );
      expect(streaked.awarded, greaterThan(plain.awarded));
    });
  });
}
