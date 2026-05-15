import org.gradle.api.tasks.Exec
import java.io.ByteArrayOutputStream
import java.util.Locale

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

fun commandExists(command: String): Boolean {
    val output = ByteArrayOutputStream()
    return try {
        exec {
            isIgnoreExitValue = true
            commandLine("cmd", "/c", "where", command)
            standardOutput = output
            errorOutput = output
        }.exitValue == 0
    } catch (_: Exception) {
        false
    }
}

android {
    namespace = "com.flamesup.nativeapp"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.flamesup.nativeapp"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"

        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

val rustOutputDir = layout.projectDirectory.dir("src/main/jniLibs").asFile
val nativeSourceDir = rootProject.layout.projectDirectory.dir("native").asFile
val nativeTempDir = file("C:/flames_android_native_rust")
val nativeTempOutputDir = file("C:/flames_android_native_jniLibs")
val hostOs = System.getProperty("os.name").lowercase(Locale.US)
val cargoCommand = if (hostOs.contains("windows")) "cargo.exe" else "cargo"

tasks.register<Exec>("buildRustNative") {
    group = "build"
    description = "Build Rust/C++ native library for Android ABIs with cargo-ndk."
    onlyIf {
        if (!commandExists("cargo")) {
            logger.warn("Skipping Rust build because cargo is not on PATH.")
            return@onlyIf false
        }
        true
    }

    doFirst {
        nativeTempDir.deleteRecursively()
        nativeTempOutputDir.deleteRecursively()
        rustOutputDir.deleteRecursively()
        nativeTempDir.mkdirs()
        nativeTempOutputDir.mkdirs()
        rustOutputDir.mkdirs()
        copy {
            from(nativeSourceDir)
            into(nativeTempDir)
            exclude("target/**")
        }
    }

    workingDir = nativeTempDir

    commandLine(
        cargoCommand,
        "ndk",
        "-t",
        "arm64-v8a",
        "-t",
        "armeabi-v7a",
        "-t",
        "x86_64",
        "-P",
        "26",
        "-o",
        nativeTempOutputDir.absolutePath,
        "build",
        "--release",
    )

    doLast {
        copy {
            from(nativeTempOutputDir)
            into(rustOutputDir)
        }
    }
}

tasks.named("preBuild") {
    dependsOn("buildRustNative")
}
