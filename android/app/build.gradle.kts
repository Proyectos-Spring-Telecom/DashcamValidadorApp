plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.dashcam"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
        // Desactivar compilación incremental para evitar problemas con rutas en diferentes unidades
        freeCompilerArgs = listOf("-Xno-param-assertions")
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.dashcam"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val releaseStore = System.getenv("DASHCAM_UPLOAD_STORE_FILE")
    val releaseStorePassword = System.getenv("DASHCAM_UPLOAD_STORE_PASSWORD")
    val releaseKeyAlias = System.getenv("DASHCAM_UPLOAD_KEY_ALIAS")
    val releaseKeyPassword = System.getenv("DASHCAM_UPLOAD_KEY_PASSWORD")
    val hasReleaseKeystore = !releaseStore.isNullOrBlank() &&
        !releaseStorePassword.isNullOrBlank() &&
        !releaseKeyAlias.isNullOrBlank() &&
        !releaseKeyPassword.isNullOrBlank()

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(releaseStore!!)
                storePassword = releaseStorePassword!!
                keyAlias = releaseKeyAlias!!
                keyPassword = releaseKeyPassword!!
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

flutter {
    source = "../.."
}

// H-13: sin keystore propio no se genera un APK/AAB de release (antes salía sin
// firmar o con la firma de debug). Solo afecta a tareas de release, no a debug.
gradle.taskGraph.whenReady {
    val pideRelease = allTasks.any { t ->
        (t.name.startsWith("assemble") || t.name.startsWith("bundle") || t.name.startsWith("package")) &&
            t.name.endsWith("Release")
    }
    val faltaKeystore = listOf(
        "DASHCAM_UPLOAD_STORE_FILE",
        "DASHCAM_UPLOAD_STORE_PASSWORD",
        "DASHCAM_UPLOAD_KEY_ALIAS",
        "DASHCAM_UPLOAD_KEY_PASSWORD",
    ).any { System.getenv(it).isNullOrBlank() }
    if (pideRelease && faltaKeystore) {
        throw GradleException(
            "Build de release sin keystore: define DASHCAM_UPLOAD_STORE_FILE, " +
                "DASHCAM_UPLOAD_STORE_PASSWORD, DASHCAM_UPLOAD_KEY_ALIAS y DASHCAM_UPLOAD_KEY_PASSWORD.",
        )
    }
}
