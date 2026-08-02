import com.flutter.gradle.FlutterExtension
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
}

val flutterExtension = extensions.getByType<FlutterExtension>()

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        load(FileInputStream(keystorePropertiesFile))
    }
}
val hasReleaseSigning = keystorePropertiesFile.exists()

android {
    namespace = "org.spectrum3847.spectrumpit"
    compileSdk = flutterExtension.compileSdkVersion
    ndkVersion = flutterExtension.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "org.spectrum3847.spectrumpit"
        minSdk = flutterExtension.minSdkVersion
        targetSdk = flutterExtension.targetSdkVersion
        versionCode = flutterExtension.versionCode
        versionName = flutterExtension.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
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
            // Release builds use the keystore declared in android/key.properties
            // (gitignored). When that file is absent (e.g. CI without secrets
            // wired up), fall back to the debug keystore so the build still
            // produces an installable APK -- the artifact just won't match the
            // release SHA-1 registered in Firebase.
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

tasks.withType<KotlinJvmCompile>().configureEach { compilerOptions.jvmTarget.set(JvmTarget.JVM_17) }

extensions.configure<FlutterExtension>("flutter") {
    source = "../.."
}
