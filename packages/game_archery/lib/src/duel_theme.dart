import 'dart:ui';

enum GroundDecor { flowers, cactus, snow }

/// A look for the duel: sky, hills, ground and what grows on it.
///
/// Picked from the match seed, so a rematch is somewhere new but a replay of
/// the same match looks the same.
class DuelTheme {
  const DuelTheme({
    required this.name,
    required this.skyTop,
    required this.skyBottom,
    required this.sun,
    required this.cloud,
    required this.farHills,
    required this.midHills,
    required this.grass,
    required this.grassDeep,
    required this.dirt,
    required this.dirtDeep,
    required this.leaf,
    required this.leafDeep,
    required this.trunk,
    required this.rock,
    required this.decoration,
    required this.windBits,
    required this.snowing,
  });

  final String name;
  final Color skyTop;
  final Color skyBottom;
  final Color sun;
  final Color cloud;
  final Color farHills;
  final Color midHills;
  final Color grass;
  final Color grassDeep;
  final Color dirt;
  final Color dirtDeep;
  final Color leaf;
  final Color leafDeep;
  final Color trunk;
  final Color rock;
  final GroundDecor decoration;

  /// What the wind carries across the screen.
  final Color windBits;
  final bool snowing;

  static const DuelTheme meadow = DuelTheme(
    name: 'MEADOW',
    skyTop: Color(0xFF3FA3E3),
    skyBottom: Color(0xFFA8DDF7),
    sun: Color(0xFFFFF3B0),
    cloud: Color(0xFFF2FAFF),
    farHills: Color(0xFF8CCBEB),
    midHills: Color(0xFF5DAE6B),
    grass: Color(0xFF58C43A),
    grassDeep: Color(0xFF3F9A2C),
    dirt: Color(0xFF8C5A34),
    dirtDeep: Color(0xFF6B4226),
    leaf: Color(0xFF3FAE4F),
    leafDeep: Color(0xFF2B8A3A),
    trunk: Color(0xFF6B4423),
    rock: Color(0xFFB9C0C7),
    decoration: GroundDecor.flowers,
    windBits: Color(0xFF7FCB3F),
    snowing: false,
  );

  static const DuelTheme canyon = DuelTheme(
    name: 'CANYON',
    skyTop: Color(0xFFFF7A59),
    skyBottom: Color(0xFFFFD27A),
    sun: Color(0xFFFFF0C2),
    cloud: Color(0xFFFFE2CF),
    farHills: Color(0xFFE08A6A),
    midHills: Color(0xFFB85C3E),
    grass: Color(0xFFD9A54A),
    grassDeep: Color(0xFFB9852E),
    dirt: Color(0xFFB0643A),
    dirtDeep: Color(0xFF8A4A28),
    leaf: Color(0xFF6FA84A),
    leafDeep: Color(0xFF4F8A34),
    trunk: Color(0xFF6B4423),
    rock: Color(0xFF9E6B52),
    decoration: GroundDecor.cactus,
    windBits: Color(0xFFE8C27A),
    snowing: false,
  );

  static const DuelTheme peaks = DuelTheme(
    name: 'PEAKS',
    skyTop: Color(0xFF3A4E8C),
    skyBottom: Color(0xFF9FB8E8),
    sun: Color(0xFFEFF4FF),
    cloud: Color(0xFFDDE6F7),
    farHills: Color(0xFF7F95C9),
    midHills: Color(0xFF5B6FA8),
    grass: Color(0xFFF4F8FF),
    grassDeep: Color(0xFFC9D6EE),
    dirt: Color(0xFF5F6B85),
    dirtDeep: Color(0xFF454F66),
    leaf: Color(0xFF2E6B55),
    leafDeep: Color(0xFF1F4F3F),
    trunk: Color(0xFF4A3526),
    rock: Color(0xFF9AA3B5),
    decoration: GroundDecor.snow,
    windBits: Color(0xFFFFFFFF),
    snowing: true,
  );

  static const List<DuelTheme> all = <DuelTheme>[meadow, canyon, peaks];

  static DuelTheme forSeed(int seed) => all[seed.abs() % all.length];
}
