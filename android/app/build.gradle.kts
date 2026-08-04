import java.util.Properties
import java.io.File
import java.io.FileInputStream
import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    // Flutter plugin after Android + Kotlin
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Single JVM target for Java + Kotlin
val jvmVersion = JavaVersion.VERSION_17

// key.properties under android/; storeFile is absolute or relative to android/
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

/**
 * Resolve release keystore from key.properties storeFile.
 * Tries several locations because CI and local historically used different paths:
 * - absolute path
 * - relative to android/ (key.properties dir)
 * - relative to android/app/
 * - filename-only under android/app/
 */
fun resolveReleaseKeystore(storePath: String): File {
    val androidDir = keystorePropertiesFile.parentFile
        ?: rootProject.projectDir
    val raw = File(storePath.trim())
    val name = raw.name
    val candidates = linkedSetOf<File>()

    if (raw.isAbsolute) {
        candidates += raw
    } else {
        candidates += androidDir.resolve(storePath)
        candidates += androidDir.resolve("app").resolve(storePath)
        candidates += androidDir.resolve(name)
        candidates += androidDir.resolve("app").resolve(name)
        // :app projectDir-relative (android/app/)
        candidates += file(storePath)
        candidates += file(name)
    }

    // Well-known names used by CI / local
    candidates += androidDir.resolve("app/release-keystore.jks")
    candidates += androidDir.resolve("app/gavra-release-key-production.keystore")
    candidates += androidDir.resolve("release-keystore.jks")

    return candidates.firstOrNull { it.isFile }
        ?: throw GradleException(
            buildString {
                appendLine("Release keystore not found for storeFile='$storePath'")
                appendLine("Tried:")
                candidates.forEach { appendLine("  - ${it.absolutePath}") }
                appendLine("Fix storeFile in android/key.properties or restore the keystore on CI.")
            },
        )
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

    signingConfigs {
        create("release") {
            val alias = (keystoreProperties["keyAlias"] as String?)?.trim()
            val storePath = (keystoreProperties["storeFile"] as String?)?.trim()
            if (!alias.isNullOrBlank() && !storePath.isNullOrBlank()) {
                keyAlias = alias
                keyPassword = keystoreProperties["keyPassword"] as String
                storePassword = keystoreProperties["storePassword"] as String
                storeFile = resolveReleaseKeystore(storePath)
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

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
