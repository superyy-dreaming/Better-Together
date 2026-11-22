import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingFile = rootProject.file("key.properties")
val releaseSigning = Properties().apply {
    if (signingFile.exists()) signingFile.inputStream().use { load(it) }
}
val pushFile = rootProject.file("push.properties")
val pushConfig = Properties().apply {
    if (pushFile.exists()) pushFile.inputStream().use { load(it) }
}
val releaseRequested = gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }
if (releaseRequested) {
    require(signingFile.exists()) { "Release signing requires android/key.properties. See config/android-key.example.properties." }
    for (key in listOf("storeFile", "storePassword", "keyAlias", "keyPassword", "applicationId")) {
        require(!releaseSigning.getProperty(key).isNullOrBlank()) { "Missing release signing property: $key" }
    }
    require(rootProject.file(releaseSigning.getProperty("storeFile")).isFile) { "Release keystore file does not exist." }
}

android {
    namespace = "app.bettertogether.better_together"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = releaseSigning.getProperty("applicationId", "app.bettertogether.better_together")
        manifestPlaceholders["JPUSH_PKGNAME"] = applicationId!!
        manifestPlaceholders["JPUSH_APPKEY"] = pushConfig.getProperty("appKey", "")
        manifestPlaceholders["JPUSH_CHANNEL"] = pushConfig.getProperty("channel", "private-beta")
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (signingFile.exists()) {
            create("release") {
                storeFile = rootProject.file(releaseSigning.getProperty("storeFile", "missing-keystore"))
                storePassword = releaseSigning.getProperty("storePassword")
                keyAlias = releaseSigning.getProperty("keyAlias")
                keyPassword = releaseSigning.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

dependencies {
    implementation("cn.jiguang.sdk:jpush:6.3.1")
    implementation("cn.jiguang.sdk:jcore:5.6.0")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
