import java.util.Properties
import java.io.FileInputStream
import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.huawei.agconnect")
}

// 🔐 PRODUCTION KEYSTORE CONFIGURATION
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.gavra013.gavra_android"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.gavra013.gavra_android"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }
    // 🔐 PRODUCTION SIGNING CONFIGURATION
    signingConfigs {
        create("release") {
            if (keystoreProperties.containsKey("keyAlias")) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                // Robust path handling for both Local and CI
                val storePath = keystoreProperties["storeFile"] as String
                storeFile = if (file(storePath).exists()) {
                    file(storePath)
                } else {
                    // Fallback to searching in app directory if not found at root path
                    file("app/$storePath")
                }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    // ✅ Validate expected release keystore when running release-related tasks
    val isReleaseTask = gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }
    if (isReleaseTask && keystoreProperties.containsKey("storeFile")) {
        val storePath = keystoreProperties["storeFile"] as String
        val resolvedFile = if (file(storePath).exists()) file(storePath) else file("app/$storePath")
        
        if (!resolvedFile.exists()) {
            throw GradleException(
                "Missing or invalid release keystore at '${resolvedFile.absolutePath}'.\n" +
                "Check key.properties or CI secrets."
            )
        }
    }

    buildTypes {
        named("release") {
            // 🚀 R8 ENABLED (2026-01-05) - smanjuje APK za ~40%
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // Import the Firebase BoM
    implementation(platform("com.google.firebase:firebase-bom:34.11.0"))

    // Add Firebase Authentication
    implementation("com.google.firebase:firebase-auth")

    // Add Firebase Cloud Messaging
    implementation("com.google.firebase:firebase-messaging")

    // Huawei Mobile Services Push (AppGallery devices / no GMS)
    implementation("com.huawei.hms:push:6.12.0.300")

    // 🚀 Google Play Core - NEW MODULAR LIBRARIES (Android 14+ compatible)
    implementation("com.google.android.play:app-update:2.1.0") {
        because("Replaces deprecated play:core for in-app updates")
    }
    implementation("com.google.android.play:review:2.0.2") {
        because("Replaces deprecated play:core for in-app reviews")
    }
}

flutter {
    source = "../.."
}
