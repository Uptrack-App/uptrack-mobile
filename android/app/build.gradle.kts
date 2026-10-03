import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// R3.1 release signing: `android/key.properties` (gitignored) points at the
// upload keystore. Absent locally and in PRs — release builds fall back to
// debug keys so `flutter run --release` keeps working. CI tags provide the
// file from the ANDROID_* secrets (see .github/workflows/ci.yml).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use(keystoreProperties::load)
}

android {
    namespace = "app.uptrack.uptrack_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications' AAR metadata; without it
        // even `assembleDebug` fails (found enabling the T050 device run).
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.uptrack.uptrack_mobile"
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

    // R3.1: declared BEFORE buildTypes — the release build type references
    // signingConfigs.getByName("release"), which fails if the config is
    // created later in evaluation order.
    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // R3.1: signed with the upload key when key.properties exists
            // (CI tags); debug keys otherwise (local dev only — never upload
            // a debug-signed artifact to a store track).
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // T056 data-message receiver posts with NotificationCompat (the
    // plugin's androidx.core is `implementation`-scoped, so the app
    // declares it explicitly rather than relying on transitivity).
    implementation("androidx.core:core:1.13.1")
    // R2.1 FCM data messages + token APIs. Compiles without
    // google-services.json; at runtime the token path returns null until
    // the M0.3 Firebase project lands (see MainActivity.replyWithToken).
    implementation(platform("com.google.firebase:firebase-bom:34.4.0"))
    implementation("com.google.firebase:firebase-messaging")
}

// R2.1: the google-services plugin requires google-services.json at
// build time, so it is applied only once the M0.3 Firebase project exists.
// Without it, debug builds compile and run (push no-ops on both ends).
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}
