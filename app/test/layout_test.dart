import 'package:elevar_play/data/points_repository.dart';
import 'package:elevar_play/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_points_repository.dart';

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

      testWidgets('the cricket mode select lays out', (tester) async {
        await pumpAt(tester, entry.value);
        await tester.tap(find.text('CRICKET'));
        await tester.pumpAndSettle();
        expect(find.text('START MATCH'), findsOneWidget);

        // CHASE is the longest description on the screen and HARD adds a
        // second line under the opposition row, so this is the tall case.
        await tester.tap(find.text('CHASE · 4'));
        await tester.tap(find.text('HARD'));
        await tester.pumpAndSettle();
        await tester.drag(find.text('FORMAT'), const Offset(0, -400));
        await tester.pumpAndSettle();
      });

      testWidgets('the racing mode select lays out', (tester) async {
        await pumpAt(tester, entry.value);
        await tester.tap(find.text('CAR\nRACING'));
        await tester.pumpAndSettle();
        expect(find.text('START RACE'), findsOneWidget);

        // Two players is the wider layout: it adds a description line and
        // removes the difficulty row.
        await tester.tap(find.text('2 PLAYERS'));
        await tester.pumpAndSettle();
      });

      testWidgets('the ping pong mode select lays out', (tester) async {
        await pumpAt(tester, entry.value);
        await tester.tap(find.text('PING\nPONG'));
        await tester.pumpAndSettle();
        expect(find.text('START MATCH'), findsOneWidget);

        await tester.tap(find.text('2 PLAYERS'));
        await tester.pumpAndSettle();
      });
    });
  }
}
