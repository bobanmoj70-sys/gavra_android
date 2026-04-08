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
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
        encoding = "UTF-8"
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
        freeCompilerArgs = listOf("-Xjvm-default=all")
    }

    defaultConfig {
        applicationId = "com.gavra013.gavra_android"
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    // 🔐 PRODUCTION SIGNING CONFIGURATION
    signingConfigs {
        create("release") {
            if (keystoreProperties.containsKey("keyAlias")) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    // ✅ Validate expected release keystore when running release-related tasks
    val isReleaseTask = gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }
    if (isReleaseTask) {
        val storeFilePath = keystoreProperties["storeFile"] as? String
        if (storeFilePath == null || storeFilePath.isBlank() || !file(storeFilePath).exists()) {
            throw GradleException(
                "Missing or invalid release keystore. Expected keystore at '${storeFilePath ?: "<undefined>"}'.\n" +
                    "Create a 'key.properties' with storeFile pointing to your keystore, or configure CI secrets: ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD."
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
