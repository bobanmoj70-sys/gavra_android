import com.android.build.gradle.LibraryExtension

// Root: repos + Flutter plugin compatibility.
// Plugin versions live only in settings.gradle.kts.

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    project.layout.buildDirectory.value(newBuildDir.dir(project.name))

    // Flutter template: plugins evaluate after :app (skip self / gradle)
    if (project.name != "gradle" && project.name != "app") {
        project.evaluationDependsOn(":app")
    }

    // Older Flutter plugins without namespace
    pluginManager.withPlugin("com.android.library") {
        val androidLibrary = extensions.findByType(LibraryExtension::class.java) ?: return@withPlugin
        if (androidLibrary.namespace != null) return@withPlugin

        val manifestFile = file("src/main/AndroidManifest.xml")
        val fromManifest =
            if (manifestFile.exists()) {
                Regex("""package\s*=\s*"([^"]+)"""")
                    .find(manifestFile.readText())
                    ?.groupValues
                    ?.getOrNull(1)
            } else {
                null
            }

        androidLibrary.namespace = fromManifest
            ?: "${project.group.toString().ifBlank { "dev.flutter" }}.${project.name.replace('-', '_')}"
    }

    if (project.name == "android_intent_plus") {
        tasks.matching {
            it.name.contains("UnitTest") || (it.name.contains("Test") && it.name.contains("compile"))
        }.configureEach { enabled = false }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
