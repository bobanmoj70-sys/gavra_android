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

// Match app compileSdk so older Flutter plugins pass CheckAarMetadata
val forcedCompileSdk = 36

subprojects {
    project.layout.buildDirectory.value(newBuildDir.dir(project.name))

    // Flutter template: plugins evaluate after :app (skip self / gradle)
    if (project.name != "gradle" && project.name != "app") {
        project.evaluationDependsOn(":app")
    }

    // Older Flutter plugins: namespace + compileSdk (many still default to 31)
    pluginManager.withPlugin("com.android.library") {
        extensions.configure<LibraryExtension>("android") {
            compileSdk = forcedCompileSdk

            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }

            if (namespace == null) {
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

                namespace = fromManifest
                    ?: "${project.group.toString().ifBlank { "dev.flutter" }}.${project.name.replace('-', '_')}"
            }
        }
    }

    // Override plugin defaults applied during evaluation.
    // evaluationDependsOn(":app") can leave some projects already evaluated.
    val forcePluginCompileSdk = {
        extensions.findByType(LibraryExtension::class.java)?.apply {
            if (compileSdk == null || compileSdk!! < forcedCompileSdk) {
                compileSdk = forcedCompileSdk
            }
        }
    }
    if (state.executed) {
        forcePluginCompileSdk()
    } else {
        afterEvaluate { forcePluginCompileSdk() }
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
