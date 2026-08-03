import java.util.Properties
import java.io.FileInputStream
import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // Flutter plugin after Android + Kotlin
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Single JVM target for Java + Kotlin
val jvmVersion = JavaVersion.VERSION_17

// key.properties under android/; storeFile relative to that root
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.gavra013.gavra_android"
    compileSdk = 36
    // Match Flutter plugins (highest required NDK; backward compatible)
    ndkVersion = "28.2.13676358"

    defaultConfig {
        applicationId = "com.gavra013.gavra_android"
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    compileOptions {
        sourceCompatibility = jvmVersion
        targetCompatibility = jvmVersion
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = jvmVersion.toString()
    }

    signingConfigs {
        create("release") {
            val alias = keystoreProperties["keyAlias"] as String?
            val storePath = keystoreProperties["storeFile"] as String?
            if (!alias.isNullOrBlank() && !storePath.isNullOrBlank()) {
                keyAlias = alias
                keyPassword = keystoreProperties["keyPassword"] as String
                storePassword = keystoreProperties["storePassword"] as String
                val store = rootProject.file(storePath)
                if (!store.isFile) {
                    throw GradleException(
                        "Release keystore not found: ${store.absolutePath}\n" +
                            "Fix storeFile in android/key.properties.",
                    )
                }
                storeFile = store
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // GMS check in MainActivity (FCM gate)
    implementation("com.google.android.gms:play-services-base:18.5.0")
}

flutter {
    source = "../.."
}
