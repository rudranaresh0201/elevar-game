import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The field is a fixed portrait rectangle and two people share the screen
  // facing each other; landscape has no meaning here.
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
      home: const HomeScreen(),
    );
  }
}
