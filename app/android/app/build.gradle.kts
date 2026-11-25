import java.io.FileInputStream
import java.util.Base64
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

val admobPropertiesFile = rootProject.file("admob.properties")
val admobProperties = Properties()
if (admobPropertiesFile.exists()) {
    admobProperties.load(FileInputStream(admobPropertiesFile))
}

val releaseAdmobAppId: String? = (
    admobProperties.getProperty("ADMOB_APP_ID")
        ?: System.getenv("ADMOB_APP_ID")
)?.trim()?.takeIf { it.isNotEmpty() }

val dartDefinesMap: Map<String, String> = (project.findProperty("dart-defines") as String?)
    ?.split(",")
    ?.mapNotNull { encoded ->
        try {
            val decoded = String(Base64.getDecoder().decode(encoded), Charsets.UTF_8)
            val idx = decoded.indexOf('=')
            if (idx > 0) decoded.substring(0, idx) to decoded.substring(idx + 1) else null
        } catch (_: Exception) {
            null
        }
    }
    ?.toMap()
    ?: emptyMap()

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
        manifestPlaceholders["admobAppId"] = "ca-app-pub-3940256099942544~3347511713"
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

            manifestPlaceholders["admobAppId"] =
                releaseAdmobAppId ?: "ca-app-pub-3940256099942544~3347511713"

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
    if (isReleaseTask) {
        val admobEnabledDefine = dartDefinesMap["ADMOB_ENABLED"]?.trim()?.lowercase()
        val hasDartBanner = !dartDefinesMap["ADMOB_BANNER_ID"].isNullOrBlank()
        val hasDartRewarded = !dartDefinesMap["ADMOB_REWARDED_ID"].isNullOrBlank()
        val isTestAppId = releaseAdmobAppId == "ca-app-pub-3940256099942544~3347511713"
        val wantsAdsEnabled = admobEnabledDefine == "true" ||
            (admobEnabledDefine != "false" && (hasDartBanner || hasDartRewarded))

        if (admobEnabledDefine == "false") {
            logger.lifecycle("[AdMob] Release derlemesi reklamlar kapalı (ADMOB_ENABLED=false) olarak yapılıyor.")
        } else if (wantsAdsEnabled && (releaseAdmobAppId == null || isTestAppId)) {
            throw GradleException(
                "\n" +
                "========================================================================\n" +
                "[HATA] Android Release Derlemesi Durduruldu!\n" +
                "Sebep: Reklamlar açık (ADMOB_ENABLED=true veya reklam birimi kimliği verilmiş) " +
                "ancak geçerli bir gerçek ADMOB_APP_ID bulunamadı.\n" +
                "\n" +
                "Çözüm Adımları:\n" +
                "1. 'app/android/admob.properties.example' dosyasını 'app/android/admob.properties' " +
                "olarak kopyalayıp ADMOB_APP_ID=... değerini girin (veya ADMOB_APP_ID ortam değişkenini ayarlayın).\n" +
                "2. Reklamsız release derlemesi için --dart-define=ADMOB_ENABLED=false kullanın.\n" +
                "========================================================================\n"
            )
        } else if (releaseAdmobAppId == null) {
            logger.warn("[AdMob] UYARI: ADMOB_APP_ID tanımlı değil; release derlemesinde reklamlar Dart kill-switch ile kapalı kalacak.")
        }
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
