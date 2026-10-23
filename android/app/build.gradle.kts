import java.io.FileInputStream
import java.util.Properties

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        load(FileInputStream(keystorePropertiesFile))
    }
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.cyrene.music"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // 启用核心库脱糖支持（flutter_local_notifications 需要）
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.cyrene.music"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion  // 核心库脱糖需要至少 API 21
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 默认应用名称
        manifestPlaceholders["appName"] = "Cyrene Music"
    }

    signingConfigs {
        create("release") {
            // 优先使用 key.properties 中的配置，如果不存在则使用默认的 cyrene-release.jks
            val defaultKeystoreFile = rootProject.file("cyrene-release.jks")
            val storeFileValue = keystoreProperties["storeFile"]?.takeIf { it.toString().isNotBlank() }
                ?: if (defaultKeystoreFile.exists()) "cyrene-release.jks" else null
            
            if (storeFileValue != null) {
                storeFile = rootProject.file(storeFileValue)
            }
            
            // 从 key.properties 读取密码和别名信息
            // 如果 key.properties 不存在，这些值将为空，构建会失败并提示需要配置签名信息
            keystoreProperties["storePassword"]?.takeIf { it.toString().isNotBlank() }?.let { 
                storePassword = it.toString() 
            }
            keystoreProperties["keyAlias"]?.takeIf { it.toString().isNotBlank() }?.let { 
                keyAlias = it.toString() 
            }
            keystoreProperties["keyPassword"]?.takeIf { it.toString().isNotBlank() }?.let { 
                keyPassword = it.toString() 
            }
        }
    }

    buildTypes {
        debug {
            manifestPlaceholders["appName"] = "Cyrene Music (Debug)"
        }

        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("release")
            manifestPlaceholders["appName"] = "Cyrene Music"
            ndk.abiFilters.clear()
            ndk.abiFilters.add("arm64-v8a")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // 核心库脱糖支持（flutter_local_notifications 需要 2.1.4+）
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // Android 12+ Splash Screen API 向后兼容库
    implementation("androidx.core:core-splashscreen:1.0.1")
}
