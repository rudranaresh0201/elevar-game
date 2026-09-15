{{flutter_js}}
{{flutter_build_config}}

// Flutter renders into #app rather than taking over <body>.
//
// That is the whole iPhone fix. Flutter's web engine reports a zero
// MediaQuery padding on iOS, so every SafeArea in the app collapses to nothing
// and, once the game is added to the home screen, the HUD draws under the
// Dynamic Island and the controls under the home indicator. #app is inset by
// the browser's own env(safe-area-inset-*) in index.html, so the engine is
// handed a rectangle that is already safe and nothing in Dart has to know.
//
// No service worker: Flutter's is deprecated, and a home-screen app pinned to
// a cached build is exactly the "she is still on the old version" bug.
_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine({
      hostElement: document.getElementById("app"),
    });
    await appRunner.runApp();
  },
});
