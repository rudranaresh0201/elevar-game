import 'package:elevar_play/data/points_repository.dart';
import 'package:elevar_play/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:elevar_play/data/profile_repository.dart';

import 'support/fake_points_repository.dart';
import 'support/fake_profile_repository.dart';

/// Screens must fit the phones people actually own.
///
/// Two real overflows were shipped and caught here rather than by looking:
/// the reward card's footer ran 36pt past a 390pt phone, and the racing control
/// cluster was 402pt wide against the 358pt one offers. Both were invisible on
/// the default 800x600 test surface, which is landscape and larger than any
/// phone this game will ever run on.
///
/// A Flutter overflow raises a `FlutterError` during layout, which fails the
/// surrounding test on its own — so simply building every screen at each size
/// is the assertion.

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
  /// The smallest Android phone still in circulation, a common mid-range
  /// device, and a big one.
  const sizes = <String, Size>{
    'small (320x640)': Size(320, 640),
    'common (390x844)': Size(390, 844),
    'large (430x932)': Size(430, 932),
  };

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ElevarPlayApp());
    await tester.pumpAndSettle();
  }

  for (final entry in sizes.entries) {
    group(entry.key, () {
      setUp(() {
        // A balance with wide numbers in it, and enough unsynced matches for
        // every chip in the header to be present at once.
        pointsRepository = FakePointsRepository(
          balanceValue: 12480,
          pending: 17,
          streakDays: 31,
        );
        profileRepository = FakeProfileRepository();
      });

      testWidgets('the hub lays out', (tester) async {
        await pumpAt(tester, entry.value);
        expect(find.text('ELEVAR'), findsOneWidget);
      });

      testWidgets('the rewards screen lays out', (tester) async {
        await pumpAt(tester, entry.value);
        // Via the points header rather than the CTA at the bottom of the
        // page: the header is pinned at the top on every size, whereas on a
        // short phone the CTA is below the fold and a ListView does not build
        // children it has not scrolled to.
        await tester.tap(find.byIcon(Icons.bolt_rounded));
        await tester.pumpAndSettle();
        expect(find.text('REWARDS'), findsOneWidget);
        // Scroll the whole catalogue past, so every card gets laid out rather
        // than only the two above the fold.
        await tester.drag(find.text('REWARDS'), const Offset(0, -1200));
        await tester.pumpAndSettle();
      });

      testWidgets('the penalty shootout mode select lays out', (tester) async {
        await pumpAt(tester, entry.value);
        await openGame(tester, 'PENALTY\nSHOOTOUT');
        expect(find.text('KICK OFF'), findsOneWidget);

        // Two players carries the longest caption on the screen. Scrolled to
        // first: on a 320pt phone it is below the fold, and a blind tap there
        // once hit KICK OFF and played a whole shootout inside this test.
        await tester.ensureVisible(find.text('2 PLAYERS'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('2 PLAYERS'));
        await tester.pumpAndSettle();
        expect(find.text('DIFFICULTY'), findsNothing);
        await tester.drag(find.text('OPPONENT'), const Offset(0, -400));
        await tester.pumpAndSettle();
      });

      testWidgets('the shooting mode select lays out', (tester) async {
        await pumpAt(tester, entry.value);
        await openGame(tester, 'SHOOTING');
        expect(find.text('START DUEL'), findsOneWidget);
        await tester.tap(find.text('HARD'));
        await tester.pumpAndSettle();
        await tester.drag(find.text('OPPONENT'), const Offset(0, -400));
        await tester.pumpAndSettle();
      });

      testWidgets('the fruit drop mode select lays out', (tester) async {
        await pumpAt(tester, entry.value);
        // The newest game is the wide featured tile, which sets its title on
        // one line.
        await openGame(tester, 'FRUIT DROP');
        expect(find.text('START'), findsOneWidget);
        await tester.ensureVisible(find.text('HARD'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('HARD'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Score 1000 in 150 drops'), findsOneWidget);
      });

      testWidgets('the leaderboard lays out', (tester) async {
        await pumpAt(tester, entry.value);
        await tester.tap(find.text('BOARD'));
        await tester.pumpAndSettle();
        expect(find.text('LEADERBOARD'), findsOneWidget);
      });

      testWidgets('the profile lays out', (tester) async {
        await pumpAt(tester, entry.value);
        await tester.tap(find.text('YOU'));
        await tester.pumpAndSettle();
        expect(find.text('YOUR PROFILE'), findsOneWidget);
        await tester.drag(find.text('AVATAR'), const Offset(0, -300));
        await tester.pumpAndSettle();
      });

      testWidgets('the cricket mode select lays out', (tester) async {
        await pumpAt(tester, entry.value);
        await openGame(tester, 'CRICKET');
        expect(find.text('START MATCH'), findsOneWidget);

        // Both rows can be below the fold on a 320pt phone, where a tap lands
        // on whatever is actually there — once, the START button.
        await tester.ensureVisible(find.text('HARD'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('HARD'));
        await tester.ensureVisible(find.text('LONG · 5'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('LONG · 5'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Score 90 to win'), findsOneWidget);
        await tester.drag(find.text('FORMAT'), const Offset(0, -400));
        await tester.pumpAndSettle();
      });

      testWidgets('the racing mode select lays out', (tester) async {
        await pumpAt(tester, entry.value);
        await openGame(tester, 'CAR\nRACING');
        expect(find.text('START RACE'), findsOneWidget);

        // Two players is the wider layout: it adds a description line and
        // removes the difficulty row.
        await tester.tap(find.text('2 PLAYERS'));
        await tester.pumpAndSettle();
      });

      testWidgets('the ping pong mode select lays out', (tester) async {
        await pumpAt(tester, entry.value);
        await openGame(tester, 'PING\nPONG');
        expect(find.text('START MATCH'), findsOneWidget);

        await tester.tap(find.text('2 PLAYERS'));
        await tester.pumpAndSettle();
      });
    });
  }
}
