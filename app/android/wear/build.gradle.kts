import java.util.Properties

// The Wear OS watch app. It shares the phone app's application id and signing key, which is what lets
// the two talk to each other through the Data Layer. Build it with
//   android\gradlew.bat :wear:assembleRelease
// and install it on the watch with adb (see packaging\wear\README.md).
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

val keyProps = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

android {
    namespace = "com.substancejournal.watch"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.substancejournal.substance_journal_app"
        minSdk = 30
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }

    signingConfigs {
        if (keyProps.containsKey("storeFile")) {
            create("release") {
                storeFile = rootProject.file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            val allowDebug = System.getenv("CI") != null || project.hasProperty("allowDebugSigning")
            signingConfig = when {
                keyProps.containsKey("storeFile") -> signingConfigs.getByName("release")
                allowDebug -> signingConfigs.getByName("debug")
                else -> throw GradleException("No android/key.properties: run scripts/make_android_keystore.ps1, or pass -PallowDebugSigning=true for a test-only build.")
            }
        }
    }

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2025.01.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.wear.compose:compose-material:1.4.1")
    implementation("androidx.wear.compose:compose-foundation:1.4.1")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("com.google.android.gms:play-services-wearable:19.0.0")
}
