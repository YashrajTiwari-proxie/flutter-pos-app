import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val localProperties =
    Properties().apply {
        val file = rootProject.file("local.properties")
        if (file.exists()) file.inputStream().use { load(it) }
    }

fun softpayProperty(key: String, default: String): String = localProperties.getProperty(key) ?: default

android {
    namespace = "com.proxiestudio.kds_pos"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.proxiestudio.kds_pos"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // SoftPay AppSwitch integrator config - real values live in android/local.properties (gitignored).
        buildConfigField("String", "SOFTPAY_INTEGRATOR_ID", "\"${softpayProperty("SOFTPAY_INTEGRATOR_ID", "Spay-YourIntegratorId")}\"")
        buildConfigField("String", "SOFTPAY_INTEGRATOR_SECRET", "\"${softpayProperty("SOFTPAY_INTEGRATOR_SECRET", "e8337ccce2db45b6be203918944f3fc8")}\"")
        buildConfigField("String", "SOFTPAY_MERCHANT_NAME", "\"${softpayProperty("SOFTPAY_MERCHANT_NAME", "YourMerchantName")}\"")
        buildConfigField("String", "SOFTPAY_TARGET", "\"${softpayProperty("SOFTPAY_TARGET", "sandbox")}\"")
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
        // Required by the SoftPay AppSwitch SDK docs so its default-implemented Kotlin
        // interface members (e.g. optional PaymentTransaction fields) compile/link correctly.
        freeCompilerArgs.add("-Xjvm-default=all")
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Real SoftPay AppSwitch SDK coordinates (per developer.softpay.io); requires the
    // Nexus repo credentials configured in the root build.gradle.kts / local.properties.
    implementation("io.softpay:softpay-client:1.9.0")

    // Printing is handled by the sunmi_flutter_plugin_printer Dart package (see pubspec.yaml),
    // which brings its own com.sunmi:printerx dependency - no native printer wiring needed here.

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
}
