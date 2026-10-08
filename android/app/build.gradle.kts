plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Provisioned by the custodian outside the repository; never fall back to debug.
val releaseSecrets = listOf("ELEVAGE_KEYSTORE_PATH", "ELEVAGE_KEYSTORE_PASSWORD",
    "ELEVAGE_KEY_ALIAS", "ELEVAGE_KEY_PASSWORD").associateWith { System.getenv(it) }
val releaseRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}
if (releaseRequested) {
    require(releaseSecrets.values.all { !it.isNullOrBlank() }) {
        "Release signing requires the four ELEVAGE signing environment variables."
    }
    val keyFile = file(releaseSecrets.getValue("ELEVAGE_KEYSTORE_PATH")!!).canonicalFile
    require(keyFile.isFile && !keyFile.toPath().startsWith(rootProject.projectDir.parentFile.canonicalFile.toPath())) {
        "Release keystore must exist outside the repository."
    }
}

android {
    namespace = "com.elevage.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17

        // 🔥 OBLIGATOIRE POUR flutter_local_notifications
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.elevage.app"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    signingConfigs {
        if (releaseSecrets.values.all { !it.isNullOrBlank() }) {
            create("permanentRelease") {
                storeFile = file(releaseSecrets.getValue("ELEVAGE_KEYSTORE_PATH")!!)
                storePassword = releaseSecrets.getValue("ELEVAGE_KEYSTORE_PASSWORD")
                keyAlias = releaseSecrets.getValue("ELEVAGE_KEY_ALIAS")
                keyPassword = releaseSecrets.getValue("ELEVAGE_KEY_PASSWORD")
            }
        }
    }
    buildTypes {
        debug {
            // Isolated installation for emulator validation, separate from customer app data.
            applicationIdSuffix = ".offlinevalidation"
        }
        release {
            signingConfig = signingConfigs.findByName("permanentRelease")
        }
    }
}

// 🔥 AJOUT OBLIGATOIRE
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    // Android test runtime must match the debug app's consistently resolved graph.
    debugImplementation("androidx.test.ext:junit:1.3.0")
    debugImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
}

flutter {
    source = "../.."
}
