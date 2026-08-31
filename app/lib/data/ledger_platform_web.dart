import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'points_repository.dart';
import 'profile_repository.dart';

/// The browser: run the same SQL against `sqlite3.wasm`, stored in IndexedDB.
///
/// This is what makes a shared link a real demo rather than a video. Points
/// earned in a browser tab survive a refresh and a phone being locked, so the
/// thing the whole hub is for — *play a game, watch a balance go up* — is
/// actually true on the web build.
///
/// Two files have to be sitting next to `index.html` for this to work:
/// `sqflite_sw.js` and `sqlite3.wasm`. Both are put there by
/// `dart run sqflite_common_ffi_web:setup`, and both are committed, because a
/// deploy that forgets them fails at the first ledger write rather than at
/// build time.
void configureLedgerForPlatform() {
  pointsRepository = SqlitePointsRepository(
    databaseFactoryOverride: databaseFactoryFfiWeb,
    // No filesystem to join a path onto — this is a key in IndexedDB.
    pathOverride: 'elevar_points.db',
  );
  // The profile and the cached board ride the same engine. A player id that
  // did not survive a refresh would put a new name on the leaderboard every
  // time somebody opened the shared link.
  profileRepository = SqliteProfileRepository(
    databaseFactoryOverride: databaseFactoryFfiWeb,
    pathOverride: 'elevar_social.db',
  );
}
