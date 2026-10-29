import java.util.Base64

// Applies before the Android/signing configuration. Also testable with a
// standalone Gradle project, without the Android SDK or an APK build.
val labWifiProperty = findProperty("elevage.labWifi") as? String
if (labWifiProperty != null && labWifiProperty != "true") throw GradleException("LAB_WIFI_CONFIG: explicit true required")
val labF3Property = findProperty("elevage.labF3") as? String
if (labF3Property != null && labF3Property != "true") throw GradleException("LAB_F3_CONFIG: explicit true required")
val encodedDefines = (findProperty("dart-defines") as? String).orEmpty()
val guardDefines = mutableMapOf<String, String>()
encodedDefines.split(',').filter { it.isNotEmpty() }.forEach { encoded ->
    val decoded = try {
        String(Base64.getDecoder().decode(encoded), Charsets.UTF_8)
    } catch (_: IllegalArgumentException) {
        throw GradleException("PILOT_CONFIG: invalid Dart definitions")
    }
    val separator = decoded.indexOf('=')
    if (separator <= 0) throw GradleException("PILOT_CONFIG: invalid Dart definition")
    val key = decoded.substring(0, separator)
    if (guardDefines.put(key, decoded.substring(separator + 1)) != null) {
        throw GradleException("PILOT_CONFIG: duplicate Dart definition")
    }
}
val guardEnvironment = guardDefines["APP_ENV"] ?: "production"
if (guardEnvironment !in listOf("production", "pilot", "lab")) {
    throw GradleException("PILOT_CONFIG: unknown environment")
}
if (labF3Property == "true" && (guardEnvironment != "lab" || guardDefines["FLUTTER_APP_FLAVOR"] != "lab")) {
    throw GradleException("LAB_F3_CONFIG: isolated package is available only in Android LAB debug")
}

val wifiRequested = labWifiProperty == "true"
if (wifiRequested != (guardDefines["LAB_TRANSPORT"] == "wifi") ||
    (wifiRequested && (labF3Property != null || guardEnvironment != "lab" ||
        guardDefines["FLUTTER_APP_FLAVOR"] != "lab" || guardDefines["LAB_TEST_CONTEXT"] != "wifi"))) {
    throw GradleException("LAB_WIFI_CONFIG: explicit isolated LAB Wi-Fi selection required")
}
val wifiAddress = guardDefines["LAB_API_HOST"].orEmpty()
if (wifiRequested && !Regex("""(?:10\.(?:[0-9]{1,3}\.){2}[0-9]{1,3}|192\.168\.[0-9]{1,3}\.[0-9]{1,3}|172\.(?:1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3})""").matches(wifiAddress)) {
    throw GradleException("LAB_WIFI_CONFIG: private IPv4 required")
}
if (wifiRequested && wifiAddress.split('.').any { part -> part.toIntOrNull()?.let { it !in 0..255 || it.toString() != part } ?: true }) {
    throw GradleException("LAB_WIFI_CONFIG: canonical private IPv4 required")
}
if (guardEnvironment != "lab" &&
    (labF3Property != null || labWifiProperty != null || guardDefines.keys.any { it.startsWith("LAB_") })) {
    throw GradleException("LAB_CONFIG: laboratory definitions are forbidden outside LAB")
}
val validatePilotTasks: (List<String>) -> Unit = labGuard@ { taskNames ->
    val lab = taskNames.any { it.contains("lab", ignoreCase = true) }
    if (lab || guardEnvironment == "lab" || guardDefines["FLUTTER_APP_FLAVOR"] == "lab") {
        val endpoint = try { java.net.URI(guardDefines["API_URL"].orEmpty()) } catch (_: Exception) { null }
        val host = guardDefines["LAB_API_HOST"].orEmpty()
        // ArtProfile tasks generate baseline-profile metadata for debug APKs;
        // they are not the Android profile build type.
        val debugArtProfile = Regex("(?:merge|compile)(?:Lab)?DebugArtProfile", RegexOption.IGNORE_CASE)
        val unsignedMetadata = "writeLabDebugSigningConfigVersions"
        val forbiddenNames = taskNames.filter { name ->
            name.contains("release", true) ||
                (name.contains("profile", true) && !debugArtProfile.matches(name)) ||
                name.contains("production", true) || name.contains("pilot", true) ||
                name.contains("install", true) || name.contains("publish", true) ||
                name.contains("distribut", true) || name.contains("upload", true) ||
                name.contains("connected", true) || name.contains("device", true) ||
                (name.contains("sign", true) && name != unsignedMetadata) ||
                name.equals("bundleLabDebug", true) || name.contains("LabDebugAndroidTest", true)
        }
        // Assembly is allowed only offline, in an explicitly isolated local tree.
        // This property never overrides URL, flavor, task or signing checks.
        if (taskNames.any { it.equals("assembleLabDebug", true) }) {
            val rootValue = findProperty("elevage.labValidationRoot") as? String
            val isolatedRoot = rootValue?.let { file(it).canonicalFile }
            val projectPath = rootProject.projectDir.canonicalFile.toPath()
            require(gradle.startParameter.isOffline && isolatedRoot != null &&
                java.io.File(rootValue!!).isAbsolute && isolatedRoot.isDirectory &&
                projectPath.startsWith(isolatedRoot.toPath()) && projectPath != isolatedRoot.toPath()) {
                "LAB_CONFIG: assembly requires offline execution in an explicit isolated validation root"
            }
        }
        if (!lab || forbiddenNames.isNotEmpty() ||
            guardEnvironment != "lab" || guardDefines["FLUTTER_APP_FLAVOR"] != "lab" ||
            endpoint == null || endpoint.scheme != "https" || endpoint.host != host ||
            host.isEmpty() || host != host.lowercase() || !host.matches(Regex("[a-z0-9]+(?:[.-][a-z0-9]+)+")) ||
            host == "onrender.com" || host.endsWith(".onrender.com") ||
            (endpoint.port !in listOf(-1,443) && !((host == "127.0.0.1" || wifiRequested) && endpoint.port == 8443)) ||
            endpoint.rawUserInfo != null || endpoint.rawQuery != null ||
            endpoint.rawFragment != null || endpoint.rawPath != "/api") {
            throw GradleException("LAB_CONFIG: lab debug requires explicit dedicated HTTPS API_URL and LAB_API_HOST; mixed/distribution builds forbidden; rejected tasks: " + forbiddenNames.take(12).joinToString())
        }
        return@labGuard
    }
    val pilot = taskNames.any { it.contains("pilot", ignoreCase = true) }
    val production = taskNames.any { it.contains("production", ignoreCase = true) }
    if (pilot || guardEnvironment == "pilot" || guardDefines["FLUTTER_APP_FLAVOR"] == "pilot") {
        if (!pilot || production || guardEnvironment != "pilot" ||
            guardDefines["API_URL"] != "https://backend-elevage-pilot.onrender.com/api" ||
            (guardDefines["FLUTTER_APP_FLAVOR"] != null && guardDefines["FLUTTER_APP_FLAVOR"] != "pilot")) {
            throw GradleException("PILOT_CONFIG: pilot flavor, APP_ENV=pilot and approved API_URL are required; mixed builds are forbidden")
        }
    } else {
        if (guardEnvironment != "production" || guardDefines["FLUTTER_APP_FLAVOR"] !in listOf(null, "production")) {
            throw GradleException("PRODUCTION_CONFIG: production environment/flavor required")
        }
        if (taskNames.any { it.contains("release", true) } &&
            guardDefines["API_URL"] !in listOf(null, "", "https://backend-elevage.onrender.com/api")) {
            throw GradleException("PRODUCTION_CONFIG: release requires the exact production HTTPS API")
        }
    }
}
validatePilotTasks(gradle.startParameter.taskNames)
gradle.taskGraph.whenReady {
    // AGP plugin CMake debug configurations can depend on this inert lifecycle
    // marker. It performs no profile compilation. Validate its actual type,
    // actions, outputs and dependencies; real profile tasks remain forbidden.
    val inertProfileMarkers = if (guardEnvironment == "lab") allTasks.filter { task ->
        task.name in setOf("preProfileBuild", "prePilotDebugBuild") &&
            task.actions.isEmpty() && task.outputs.files.files.isEmpty() &&
            generateSequence<Class<*>>(task.javaClass) { type -> type.superclass }.any {
                it.name == "com.android.build.gradle.internal.tasks.AndroidVariantTask"
            } && task.taskDependencies.getDependencies(task).all { it.name == "preBuild" }
    }.toSet() else emptySet()
    validatePilotTasks(allTasks.filterNot { it in inertProfileMarkers }.map { it.name })
    if (guardEnvironment == "lab") {
        allTasks.filter { it.name == "writeLabDebugSigningConfigVersions" }.forEach {
            require(generateSequence<Class<*>>(it.javaClass) { type -> type.superclass }.any { type ->
                type.name == "com.android.build.gradle.internal.tasks.SigningConfigVersionsWriterTask"
            }) {
                "LAB_CONFIG: only AGP unsigned signing-version metadata is permitted"
            }
        }
        val androidExtension = extensions.findByName("android")
        if (androidExtension != null) {
            val types = androidExtension.javaClass.getMethod("getBuildTypes").invoke(androidExtension)
            val debug = types.javaClass.getMethod("getByName", String::class.java).invoke(types, "debug")
            require(debug.javaClass.getMethod("getSigningConfig").invoke(debug) == null) {
                "LAB_CONFIG: lab debug must have no signing identity"
            }
        }
    }
}
