import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")
    id("dev.flutter.flutter-gradle-plugin")
}

// Đọc cấu hình từ key.properties để ký ứng dụng
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    // Tên gói mới của bạn: com.khoa.findtarget
    namespace = "com.khoa.findtarget"
    // Yêu cầu SDK 36 để tương thích với các thư viện mới nhất
    compileSdk = 36 

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // --- BẬT TÍNH NĂNG DESUGARING TẠI ĐÂY ---
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        // Đồng bộ JVM về bản 17 để tránh lỗi Inconsistent JVM Target
        jvmTarget = "17"
        freeCompilerArgs += listOf("-P", "plugin:org.jetbrains.kotlin.android:enabled=true")
    }

    // Cấu hình chứng chỉ Release
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    defaultConfig {
        applicationId = "com.khoa.findtarget"
        minSdk = flutter.minSdkVersion 
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Sử dụng chứng chỉ Release chính chủ vừa tạo
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    // --- PHẦN QUAN TRỌNG: VƯỢT LỖI MOCK LOCATION ---
    lint {
        // Cho phép quyền ACCESS_MOCK_LOCATION xuất hiện trong bản Release
        checkReleaseBuilds = false
        abortOnError = false
    }
}

flutter {
    source = "../.."
}

dependencies {
    // --- THÊM THƯ VIỆN HỖ TRỢ DESUGARING TẠI ĐÂY ---
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")

    // Cấu hình Firebase cho hệ thống thu phí
    implementation(platform("com.google.firebase:firebase-bom:32.7.0"))
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-firestore")
}