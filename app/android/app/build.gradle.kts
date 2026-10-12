plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// flutter_live2d 1.0.2 ships ES2 shader sources but does not package Android
// assets. Its native loader requires assets/FrameworkShaders/<name>; missing
// programs otherwise surface as misleading GL_INVALID_VALUE attrib errors.
// Keep the SDK files in the dependency cache, not in this repository.
val live2dShaderSource = project(":flutter_live2d").layout.projectDirectory.dir(
    "src/main/cpp/CubismFramework/Rendering/OpenGL/Shaders/StandardES"
)
val live2dShaderAssets = layout.buildDirectory.dir("generated/live2dShaderAssets")
val syncLive2dShaders by tasks.registering(Sync::class) {
    from(live2dShaderSource) {
        include("*.vert", "*.frag")
        into("FrameworkShaders")
    }
    into(live2dShaderAssets)
    doFirst {
        check(live2dShaderSource.file("VertShaderSrc.vert").asFile.isFile) {
            "Live2D StandardES shaders missing: check the flutter_live2d dependency"
        }
        check(live2dShaderSource.file("FragShaderSrc.frag").asFile.isFile) {
            "Live2D StandardES fragment shader missing"
        }
    }
}

tasks.named("preBuild") { dependsOn(syncLive2dShaders) }

android {
    // AGP 9 rejects Provider in SourceSet; preBuild above carries the task dependency.
    sourceSets.getByName("main").assets.srcDir(live2dShaderAssets.get().asFile)
    namespace = "com.systempanel.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.systempanel.app"
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
    }
}

flutter {
    source = "../.."
}
