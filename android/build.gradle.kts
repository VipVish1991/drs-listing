allprojects {
    repositories {
        google()
        mavenCentral()
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
    project.evaluationDependsOn(":app")
}

// AGP 8 requires every module to declare a `namespace`, but legacy plugins
// (e.g. upi_india 3.0.1, written before AGP 8) only carry a `package`
// attribute in their AndroidManifest.xml. Inject the manifest package as
// the namespace so those plugin modules still configure and build.
// `plugins.withId` runs the instant the android-library plugin is applied —
// before its variants are created — so the namespace is in place in time.
subprojects {
    plugins.withId("com.android.library") {
        val androidExt = extensions.findByName("android")
        if (androidExt is com.android.build.gradle.LibraryExtension &&
            androidExt.namespace.isNullOrEmpty()
        ) {
            val manifest = project.file("src/main/AndroidManifest.xml")
            val pkg = if (manifest.exists()) {
                Regex("package\\s*=\\s*\"([^\"]+)\"")
                    .find(manifest.readText())
                    ?.groupValues
                    ?.get(1)
            } else {
                null
            }
            androidExt.namespace = pkg ?: project.name
        }
    }
}

// Force a consistent JVM target for Kotlin across all Android subprojects
// (including plugins) to match the Java 17 compileOptions. Without this,
// plugin modules compile Kotlin at the Gradle JDK's target (e.g. 21), causing
// "Inconsistent JVM Target Compatibility" build failures.
subprojects {
    project.plugins.withId("org.jetbrains.kotlin.android") {
        extensions.configure<org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension> {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
