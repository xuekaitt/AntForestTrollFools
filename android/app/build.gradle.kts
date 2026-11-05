plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.antmanor.automation"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.antmanor.automation"
        minSdk = 26
        targetSdk = 34
        versionCode = 4
        versionName = "1.1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

// 不引入任何第三方依赖：仅使用 Android Framework API，便于离线构建与安全审查。
dependencies {
}
