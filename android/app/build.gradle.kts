import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firma di release: dati NON versionati in android/key.properties
// (storeFile, storePassword, keyAlias, keyPassword). Nessun segreto nel
// repository: key.properties/*.jks/*.keystore sono nel .gitignore.
val keystorePropertiesFile = rootProject.file("key.properties")

android {
    namespace = "it.bluescorpion.haccpass"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Richiesto da flutter_local_notifications (date/time API).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "it.bluescorpion.haccpass"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                val keystoreProperties = Properties()
                keystoreProperties.load(FileInputStream(keystorePropertiesFile))
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
            // Regole per ML Kit (solo script Latin incluso): vedi
            // proguard-rules.pro.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

// La firma di release si verifica SOLO quando una build di release è
// effettivamente pianificata (il blocco buildTypes è valutato anche per
// il debug): senza key.properties si fallisce con messaggio chiaro, MAI
// con un ripiego sulla chiave di debug.
gradle.taskGraph.whenReady {
    val buildingRelease = allTasks.any {
        it.name.contains("Release", ignoreCase = true)
    }
    if (buildingRelease && !keystorePropertiesFile.exists()) {
        throw GradleException(
            "Impossibile firmare la build di release: manca " +
                "android/key.properties. Crea la keystore di upload e " +
                "compila storeFile/storePassword/keyAlias/keyPassword " +
                "(procedura in docs/identificativi.md)."
        )
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

flutter {
    source = "../.."
}
