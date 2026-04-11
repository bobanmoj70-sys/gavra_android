import java.util.Properties
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.Base64
import org.gradle.api.GradleException

// 🔐 AUTOMATSKO PARSIRANJE .ENV TAJNI PRE INICIJALIZACIJE PLUGINA
val envFile = rootProject.file("../.env")
if (envFile.exists()) {
    val envProps = Properties()
    envProps.load(FileInputStream(envFile))
    
    // Obnavljanje Google Services JSON-a
    val googleServicesB64 = envProps.getProperty("GOOGLE_SERVICES_JSON_BASE64")
    if (!googleServicesB64.isNullOrEmpty()) {
        val bytes = Base64.getDecoder().decode(googleServicesB64.replace("\n", "").trim())
        val outFile = file("google-services.json")
        FileOutputStream(outFile).use { it.write(bytes) }
    }
    
    // Obnavljanje AGConnect Services JSON-a
    val agconnectServicesB64 = envProps.getProperty("AGCONNECT_SERVICES_JSON_BASE64")
    if (!agconnectServicesB64.isNullOrEmpty()) {
        val bytes = Base64.getDecoder().decode(agconnectServicesB64.replace("\n", "").trim())
        val outFile = file("agconnect-services.json")
        FileOutputStream(outFile).use { it.write(bytes) }
    }
    
    // Obnavljanje Play Store Key JSON-a
    val playStoreB64 = envProps.getProperty("PLAY_STORE_KEY_JSON_BASE64")
    if (!playStoreB64.isNullOrEmpty()) {
        val bytes = Base64.getDecoder().decode(playStoreB64.replace("\n", "").trim())
        val outFile = rootProject.file("../google-play-mcp/play-store-key.json")
        outFile.parentFile.mkdirs()
        FileOutputStream(outFile).use { it.write(bytes) }
    }

    // Automatsko kreiranje key.properties fajla iz .env zapisa (Lokalno okruženje)
    val keystorePropsFile = rootProject.file("key.properties")
    val storePass = envProps.getProperty("ANDROID_STORE_PASSWORD")
    if (!storePass.isNullOrEmpty() && !keystorePropsFile.exists()) {
        val keyProps = Properties()
        keyProps.setProperty("storePassword", storePass)
        keyProps.setProperty("keyPassword", envProps.getProperty("ANDROID_KEY_PASSWORD", ""))
        keyProps.setProperty("keyAlias", envProps.getProperty("ANDROID_KEY_ALIAS", ""))
        keyProps.setProperty("storeFile", envProps.getProperty("ANDROID_STORE_FILE", ""))
        FileOutputStream(keystorePropsFile).use { keyProps.store(it, "Auto-generated from .env") }
    }
}

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
        minSdk = maxOf(flutter.minSdkVersion, 23)
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
    implementation(platform("com.google.firebase:firebase-bom:34.12.0"))

    // Add Firebase Authentication
    implementation("com.google.firebase:firebase-auth")

    // Add Firebase Cloud Messaging
    implementation("com.google.firebase:firebase-messaging")

    // Add Firebase App Check (Play Integrity)
    implementation("com.google.firebase:firebase-appcheck-playintegrity")

    // Huawei Mobile Services Push (AppGallery devices / no GMS)
    implementation("com.huawei.hms:push:6.12.0.300")

    // 🚀 Google Play Core - NEW MODULAR LIBRARIES (Android 14+ compatible)
    implementation("com.google.android.play:integrity:1.6.0")
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
