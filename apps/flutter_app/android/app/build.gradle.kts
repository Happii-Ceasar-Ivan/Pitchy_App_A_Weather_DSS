import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing (P-08). The release key lives outside the repo; the
// git-ignored android/key.properties points to it:
//   storeFile=D:/secure/pitchy-release.jks
//   storePassword=...   keyAlias=pitchy   keyPassword=...
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
if (hasReleaseKey) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

// Flutter passes --dart-define values to Gradle base64-encoded. A build with
// PITCHY_USE_MOCKS=false talks to the real backend: a "live" build.
val dartDefines: Map<String, String> =
    (project.findProperty("dart-defines") as String?)
        ?.split(",")
        ?.filter { it.isNotBlank() }
        ?.map { String(Base64.getDecoder().decode(it)) }
        ?.mapNotNull { entry ->
            val i = entry.indexOf('=')
            if (i < 0) null else entry.substring(0, i) to entry.substring(i + 1)
        }
        ?.toMap()
        ?: emptyMap()
val isLiveBuild = dartDefines["PITCHY_USE_MOCKS"] == "false"

// A live release must be signed with the release key, never the debug key
// (an APK signed with a debug key can't be updated by a release-signed one).
// Mock release builds may still use the debug key: they show "Demo data" on
// every screen and are for testing only.
gradle.taskGraph.whenReady {
    val releasing = allTasks.any { it.name == "assembleRelease" || it.name == "bundleRelease" }
    if (releasing && isLiveBuild && !hasReleaseKey) {
        throw GradleException(
            "Live release build without android/key.properties. " +
                "Create the release key first (docs/decisions/release-signing.md, P-08); " +
                "a debug-signed live APK must never be published.",
        )
    }
}

android {
    namespace = "ph.pitchy.pitchy"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "ph.pitchy.pitchy"
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

    signingConfigs {
        create("release") {
            if (hasReleaseKey) {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    // Store native libraries compressed in the APK (P-08 size audit,
    // 2026-11-26): the universal APK downloads at about half the size.
    // Android unpacks them on install, so installed size is a little larger.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    buildTypes {
        release {
            // The release key when there is one; otherwise the debug key, which
            // the check above allows only for mock (demo) builds.
            signingConfig =
                if (hasReleaseKey) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
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
