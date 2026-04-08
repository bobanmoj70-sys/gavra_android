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
