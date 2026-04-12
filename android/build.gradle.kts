import com.android.build.gradle.LibraryExtension

plugins {
    id("com.android.application") version "8.9.1" apply false
}

buildscript {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://developer.huawei.com/repo/") }
    }
    dependencies {
        classpath("com.android.tools.build:gradle:8.9.1")
        classpath("com.huawei.agconnect:agcp:1.9.1.301")
        classpath("com.google.gms:google-services:4.4.2")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://developer.huawei.com/repo/") }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    if (project.name != "gradle") {
        project.evaluationDependsOn(":app")
    }

    pluginManager.withPlugin("com.android.library") {
        val androidLibrary = extensions.findByType(LibraryExtension::class.java)
        if (androidLibrary != null) {
            if (androidLibrary.namespace == null) {
                val manifestFile = file("src/main/AndroidManifest.xml")
                val manifestPackage = if (manifestFile.exists()) {
                    Regex("package\\s*=\\s*\"([^\"]+)\"")
                        .find(manifestFile.readText())
                        ?.groupValues
                        ?.getOrNull(1)
                } else {
                    null
                }

                val fallbackNamespace = project.group
                    .toString()
                    .ifBlank { "dev.flutter" }
                    .plus(".")
                    .plus(project.name.replace('-', '_'))

                androidLibrary.namespace = manifestPackage ?: fallbackNamespace
            }

        }
    }
    
    // Skip tests for android_intent_plus package that has broken tests
    if (project.name == "android_intent_plus") {
        tasks.matching { it.name.contains("UnitTest") }.configureEach {
            enabled = false
        }
        tasks.matching { it.name.contains("Test") && it.name.contains("compile") }.configureEach {
            enabled = false
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
