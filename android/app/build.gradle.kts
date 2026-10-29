import java.security.KeyStore
import java.security.MessageDigest
import java.util.Base64

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

apply(from = rootProject.file("pilot-guard.gradle.kts"))

// Provisioned by the custodian outside the repository; never fall back to debug.
val labRequested = gradle.startParameter.taskNames.any { it.contains("lab", ignoreCase = true) } ||
    (findProperty("dart-defines") as? String).orEmpty().split(',').any {
        try { String(Base64.getDecoder().decode(it)) in listOf("APP_ENV=lab", "FLUTTER_APP_FLAVOR=lab") }
        catch (_: IllegalArgumentException) { false }
    }
val labF3 = findProperty("elevage.labF3") == "true"
val labWifi = findProperty("elevage.labWifi") == "true"
val releaseSecrets = listOf("ELEVAGE_KEYSTORE_PATH", "ELEVAGE_KEYSTORE_PASSWORD",
    "ELEVAGE_KEY_ALIAS", "ELEVAGE_KEY_PASSWORD").associateWith { if (labRequested) null else System.getenv(it) }
val releaseRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}
val validateReleaseSigning = {
    require(releaseSecrets.values.all { !it.isNullOrBlank() }) {
        "Release signing requires the four ELEVAGE signing environment variables."
    }
    val keyFile = file(releaseSecrets.getValue("ELEVAGE_KEYSTORE_PATH")!!).canonicalFile
    require(keyFile.isFile && !keyFile.toPath().startsWith(rootProject.projectDir.parentFile.canonicalFile.toPath())) {
        "Release keystore must exist outside the repository."
    }
    try {
        val store = KeyStore.getInstance(keyFile, releaseSecrets.getValue("ELEVAGE_KEYSTORE_PASSWORD")!!.toCharArray())
        val alias = releaseSecrets.getValue("ELEVAGE_KEY_ALIAS")!!
        require(store.isKeyEntry(alias))
        require(store.getKey(alias, releaseSecrets.getValue("ELEVAGE_KEY_PASSWORD")!!.toCharArray()) is java.security.PrivateKey)
        (store.getCertificate(alias) as java.security.cert.X509Certificate).checkValidity()
        if (gradle.startParameter.taskNames.any { it.contains("pilot", ignoreCase = true) }) {
            val fingerprint = MessageDigest.getInstance("SHA-256")
                .digest(store.getCertificate(alias).encoded)
                .joinToString("") { "%02X".format(it) }
            require(alias == "elevage-release" && fingerprint ==
                "999DD8507273DF8F1C06A4731D1528E01BE1E13B9CA48F438CD74347B4FFE774")
        }
    } catch (error: Exception) {
        // Never include provider exception text, which can contain secret inputs.
        throw GradleException("Release signing credentials are invalid or the certificate has expired.")
    }
}
if (releaseRequested) validateReleaseSigning()
// Also guard aggregate tasks such as "build", whose graph includes release tasks.
gradle.taskGraph.whenReady {
    if (allTasks.any { it.name.contains("release", ignoreCase = true) }) {
        validateReleaseSigning()
    }
}

android {
    namespace = "com.elevage.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17

        // ðŸ”¥ OBLIGATOIRE POUR flutter_local_notifications
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

    flavorDimensions += "environment"
    productFlavors {
        create("lab") {
            dimension = "environment"
            applicationIdSuffix = ".lab"
        }
        create("production") { dimension = "environment" }
        create("pilot") {
            dimension = "environment"
            applicationIdSuffix = ".pilot"
        }
    }

    // Register flavor/build-type source sets before their dependency buckets.
    // AGP creates combined variant configurations later during evaluation.
    sourceSets {
        maybeCreate("productionDebug")
        maybeCreate("pilotDebug")
        maybeCreate("labDebug")
        if (labF3) getByName("labDebug").res.srcDir("src/labF3/res")
        if (labWifi) getByName("labDebug").res.srcDir("src/labWifi/res")
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
            if (labRequested) signingConfig = null // E2 verification is unsigned.
            // Isolated installation for emulator validation, separate from customer app data.
            applicationIdSuffix = if (labWifi) ".wifivalidation" else if (labF3) ".offlinevalidation.f3" else ".offlinevalidation"
        }
        release {
            signingConfig = signingConfigs.findByName("permanentRelease")
        }
    }
}

// ðŸ”¥ AJOUT OBLIGATOIRE
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    // Keep production/pilot debug behavior unchanged; lab app has no test runtime.
    add("productionDebugImplementation", "androidx.test.ext:junit:1.3.0")
    add("productionDebugImplementation", "androidx.test:runner:1.7.0")
    add("pilotDebugImplementation", "androidx.test.ext:junit:1.3.0")
    add("pilotDebugImplementation", "androidx.test:runner:1.7.0")
    add("labDebugCompileOnly", "androidx.test.ext:junit:1.3.0")
    add("labDebugCompileOnly", "androidx.test:runner:1.7.0")
    constraints {
        // Removing test-only edges must not downgrade this app runtime library.
        add("labDebugRuntimeOnly", "androidx.concurrent:concurrent-futures:1.2.0")
    }
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
}

// integration_test's FlutterTestRunner uses AndroidX only when invoked by an
// instrumented test. Its registered IntegrationTestPlugin and screenshot code
// do not use AndroidX Test. Keep compile/test configurations intact, and remove
// only that test runtime from the principal lab APK. No manifest suppression.
configurations.configureEach {
    if (name == "labDebugRuntimeClasspath") {
        exclude(group = "androidx.test")
        exclude(group = "androidx.test.ext")
        exclude(group = "androidx.test.espresso")
        exclude(group = "androidx.test.services")
    }
}

flutter {
    source = "../.."
}
