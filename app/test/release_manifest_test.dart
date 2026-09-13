import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The release APK could not reach the leaderboard: Flutter declares INTERNET
/// only in the debug and profile manifests, so every build a developer runs
/// works and the one a player installs does not. Nothing on a test device
/// would ever show it.
void main() {
  test('the release manifest asks for internet access', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android.permission.INTERNET'));
  });
}
