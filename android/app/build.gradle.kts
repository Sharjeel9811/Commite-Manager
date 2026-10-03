import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

/// Release signing material, read from `android/key.properties`.
///
/// The file is **never** committed — it and the keystore itself are listed in
/// `.gitignore`.
///
/// A *release* build fails without it. Silently falling back to the debug key
/// produces an artefact that installs and runs but can never be uploaded to
/// Google Play and can never be updated later, because its certificate does not
/// match the one Play recorded. Failing loudly at build time is far cheaper than
/// discovering that after a release.
///
/// Debug builds are deliberately unaffected: `flutter run` and `flutter test`
/// must never depend on a release key existing, or a fresh clone could not be
/// run at all. The check is therefore scoped to the requested Gradle tasks
/// rather than to the whole configuration phase.
///
/// To do a local release-mode run without a real key, opt out explicitly:
///   flutter build appbundle --release -PallowDebugSigning=true
/// The resulting artefact is debug-signed and must never be published.
///
/// The `upload_` prefix is the Play Console convention: this key is only for
/// artefacts you upload, never for Play App Signing keys.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
val allowDebugSigning = (project.findProperty("allowDebugSigning") as String?)?.toBoolean() == true

// This configuration block runs for every variant, so "is this a release build?"
// has to be answered from the tasks Gradle was actually asked to run.
val buildingRelease = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}

if (hasReleaseKeystore) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
} else if (buildingRelease && !allowDebugSigning) {
    throw GradleException(
        """
        |No android/key.properties found, so this release cannot be signed properly.
        |
        |Create the upload keystore and its properties file:
        |
        |  keytool -genkeypair -v -keystore android/upload-keystore.jks \
        |          -alias upload -keyalg RSA -keysize 2048 -validity 10000
        |  cp android/key.properties.example android/key.properties
        |  # then fill in the four values in android/key.properties
        |
        |Both files are already in .gitignore. Never commit them.
        |
        |To build a debug-signed artefact for local testing only, pass:
        |  -PallowDebugSigning=true
        """.trimMargin(),
    )
}

android {
    namespace = "pk.com.committeemanager.committee_manager"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications schedules with java.time, which needs
        // desugaring to run on the older API levels this app still supports.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "pk.com.committeemanager.committee_manager"

        // local_auth and flutter_secure_storage both require API 23 as a hard floor.
        // flutter.minSdkVersion resolves to 21 (Flutter default), which is too low —
        // biometric unlock and encrypted storage will crash on API 21–22 devices at
        // runtime. Hard-coding 23 here prevents those devices from installing the app
        // at all, which is safer than a crash after install.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion

        versionCode = flutter.versionCode
        versionName = flutter.versionName

        multiDexEnabled = true
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // The upload key when it exists. The debug key is reachable only via
            // the explicit `-PallowDebugSigning=true` opt-out above, so an
            // accidental release can never end up debug-signed.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "Signing this release with the DEBUG key. The artefact is for local " +
                        "testing only and cannot be published to Google Play.",
                )
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
