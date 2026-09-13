import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/ledger_platform.dart';
import 'data/live_board.dart';
import 'data/supabase_board.dart';
import 'screens/shell_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Points are stored in SQLite everywhere; only the engine differs. Called
  // before anything can read a balance.
  configureLedgerForPlatform();
  // The realtime board, if a server is compiled in. Needs no network to
  // start, so it never delays the app opening.
  await startLiveBoard();
  // Put this player on the board as soon as the app opens, not only after
  // their next match — otherwise a new install is invisible until then.
  unawaited(syncProfileToBoard());
  // The field is a fixed portrait rectangle and two people share the screen
  // facing each other; landscape has no meaning here. Both of these are no-ops
  // in a browser, which is fine — the layout is portrait-first regardless.
  unawaited(SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]));
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
  runApp(const ElevarPlayApp());
}

class ElevarPlayApp extends StatelessWidget {
  const ElevarPlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Elevar Play',
      debugShowCheckedModeBanner: false,
      theme: ElevarTheme.build(),
      home: const ElevarShell(),
    );
  }
}
