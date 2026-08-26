/// Picks the storage engine for the points ledger.
///
/// The ledger is the same hand-written SQL everywhere — the only thing that
/// differs is what runs it. On Android and iOS that is the platform's own
/// SQLite; in a browser it is `sqlite3.wasm` behind a service worker, backed by
/// IndexedDB. Both speak `DatabaseFactory`, which is why
/// [SqlitePointsRepository] already took one as a constructor argument and
/// nothing about the schema, the daily cap or the outbox had to learn that the
/// web exists.
///
/// The conditional export is not decoration: `sqflite_common_ffi_web` reaches
/// for `dart:js_interop` and will not compile into an APK.
library;

export 'ledger_platform_io.dart'
    if (dart.library.js_interop) 'ledger_platform_web.dart';
