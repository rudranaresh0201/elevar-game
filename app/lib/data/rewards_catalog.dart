import 'package:design_system/design_system.dart';
import 'package:flutter/painting.dart';

/// One thing EP can be turned into.
class Reward {
  const Reward({
    required this.id,
    required this.brand,
    required this.title,
    required this.detail,
    required this.costPoints,
    required this.accent,
  });

  final String id;
  final String brand;
  final String title;
  final String detail;
  final int costPoints;
  final Color accent;
}

/// The reward catalogue.
///
/// A local stand-in for the server's `rewards_catalog` table (`docs/PLAN.md`
/// §7). It is hard-coded here because redemption itself is Phase 5 and a
/// catalogue that cannot be changed without an app release is the wrong shape
/// for a real one — the point of showing it now is that a player can see what
/// they are earning towards from their very first race, which is most of why
/// they play a second.
///
/// The prices are set against the economy in `docs/PLAN.md` §6.2: a 300 EP
/// daily cap means the cheapest reward is about two good days and the dearest
/// is about a fortnight of steady play. Those numbers are what bound the
/// voucher liability, so they are business decisions rather than UI ones —
/// change them here and in `scoring.ts` together.
abstract final class RewardsCatalog {
  static const List<Reward> all = <Reward>[
    Reward(
      id: 'free_shipping',
      brand: 'ELEVAR SPORTS',
      title: 'FREE SHIPPING',
      detail: 'On any single order. No minimum.',
      costPoints: 300,
      accent: ElevarColors.table,
    ),
    Reward(
      id: 'off_100',
      brand: 'ELEVAR SPORTS',
      title: '₹100 OFF',
      detail: 'Any order, any pair.',
      costPoints: 500,
      accent: ElevarColors.ball,
    ),
    Reward(
      id: 'off_250',
      brand: 'ELEVAR SPORTS',
      title: '₹250 OFF',
      detail: 'On orders over ₹1,499.',
      costPoints: 1200,
      accent: RacingColors.carP2,
    ),
    Reward(
      id: 'early_drop',
      brand: 'ELEVAR SPORTS',
      title: 'EARLY ACCESS',
      detail: '24 hours before anyone else on the next drop.',
      costPoints: 2000,
      accent: ElevarColors.p2,
    ),
    Reward(
      id: 'off_500',
      brand: 'ELEVAR SPORTS',
      title: '₹500 OFF',
      detail: 'On orders over ₹2,499.',
      costPoints: 2200,
      accent: ElevarColors.p1,
    ),
  ];
}
