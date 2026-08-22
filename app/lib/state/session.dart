import 'package:flutter/foundation.dart';

/// Points earned since the app opened.
///
/// Phase 1 has no backend and no local database yet, so this is in memory only
/// and is labelled "pending sync" in the UI — which is not a placeholder excuse
/// but exactly the state these points will be in once Phase 2 lands. Matches
/// played offline queue locally and settle when the device reconnects, so an
/// interface for unsynced points has to exist either way.
class SessionPoints extends ChangeNotifier {
  int _pending = 0;
  int _matchesToday = 0;

  int get pending => _pending;
  int get matchesToday => _matchesToday;

  void record(int points) {
    _pending += points;
    _matchesToday++;
    notifyListeners();
  }
}

/// Single instance for Phase 1. Becomes a repository backed by drift and the
/// sync outbox in Phase 2.
final SessionPoints sessionPoints = SessionPoints();
