pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

// Single source of truth for plugin versions (app module applies without re-declaring versions).
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // Stay on AGP 8.11.x — AGP 9.0.0 breaks CI with:
    //   minifyReleaseWithR8: Supplied proguard configuration does not exist:
    //   .../default_proguard_files/global/proguard-android-optimize.txt-9.0.0
    // (ExtractProguardFiles does not always run before R8 on a clean checkout.)
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
    id("com.google.gms.google-services") version "4.4.2" apply false
}

include(":app")
