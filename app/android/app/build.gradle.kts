import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasKeyProperties = keystorePropertiesFile.exists()

if (hasKeyProperties) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.kelimevs.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.kelimevs.app"
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
        if (hasKeyProperties) {
            create("release") {
                val storePath = keystoreProperties.getProperty("storeFile")
                val storeFileCandidate = if (storePath != null) file(storePath) else null
                storeFile = if (storeFileCandidate != null && storeFileCandidate.isAbsolute) {
                    storeFileCandidate
                } else if (storePath != null) {
                    rootProject.file(storePath)
                } else {
                    null
                }
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasKeyProperties) {
                signingConfig = signingConfigs.getByName("release")
            }

            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

// Release derlemesi istendiğinde key.properties yoksa debug ile sessizce imzalamayı engelle,
// anlaşılır bir hata ile derlemeyi durdur.
gradle.taskGraph.whenReady {
    val isReleaseTask = allTasks.any { task ->
        val name = task.name.lowercase()
        (name.contains("release") && (name.contains("bundle") || name.contains("assemble") || name.contains("package")))
    }
    if (isReleaseTask && !hasKeyProperties) {
        throw GradleException(
            "\n" +
            "========================================================================\n" +
            "[HATA] Android Release Derlemesi Durduruldu!\n" +
            "Sebep: 'app/android/key.properties' imzalama yapılandırma dosyası bulunamadı.\n" +
            "\n" +
            "Çözüm Adımları:\n" +
            "1. 'app/android/key.properties.example' dosyasını kopyalayarak 'app/android/key.properties' oluşturun.\n" +
            "2. İçindeki 'storeFile', 'storePassword', 'keyAlias', 'keyPassword' alanlarını doldurun.\n" +
            "3. Windows kullanıcıları: Dosya yolunda ters eğik çizgi (\\) yerine ileri eğik çizgi (/) kullanın.\n" +
            "\n" +
            "Güvenlik Notu: Release derlemesinin debug anahtarıyla sessizce imzalanmasına izin verilmez.\n" +
            "========================================================================\n"
        )
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
