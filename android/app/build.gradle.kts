plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the
    id("dev.flutter.flutter-gradle-plugin")
    // 👇 THÊM DÒNG NÀY VÀO CUỐI DANH SÁCH PLUGINS
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.agrico_deepseek"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.agrico_deepseek"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    // 👇 THÊM TOÀN BỘ PHẦN NÀY VÀO CUỐI FILE (Block dependencies)
    implementation(platform("com.google.firebase:firebase-bom:34.17.0"))
    
    // Khai báo các dịch vụ Firebase bạn muốn dùng (Bỏ comment dòng nào bạn cần)
    implementation("com.google.firebase:firebase-auth") 
    implementation("com.google.firebase:firebase-firestore")
    // implementation("com.google.firebase:firebase-storage") // Nếu cần lưu ảnh
}