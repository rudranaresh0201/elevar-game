/// Android, iOS, desktop: the default `sqflite` factory is already correct.
///
/// Deliberately does nothing. The alternative — branching inside
/// `points_repository.dart` — would put a `kIsWeb` check in the middle of the
/// one file that has to stay readable as a schema.
void configureLedgerForPlatform() {}
