plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.elevarsports.elevar_play"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.elevarsports.elevar_play"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Every APK handed out so far was signed with one developer machine's
    // debug key (SHA-256 37:5C:9F:15…). Android only installs an update signed
    // by the same key, so CI must sign with that exact keystore — passed by
    // path in ELEVAR_KEYSTORE, because where AGP looks for its own debug key
    // on a CI runner is not something to leave to chance (the first CI build
    // silently generated a fresh one). Locally, unset, nothing changes.
    val sharedKeystore = System.getenv("ELEVAR_KEYSTORE")?.let { file(it) }?.takeIf { it.exists() }
    signingConfigs {
        if (sharedKeystore != null) {
            create("shared") {
                storeFile = sharedKeystore
                storePassword = "android"
                keyAlias = "androiddebugkey"
                keyPassword = "android"
            }
        }
    }

    buildTypes {
        release {
            // TODO: a real upload key before the Play Store.
            signingConfig = signingConfigs.getByName(if (sharedKeystore != null) "shared" else "debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
