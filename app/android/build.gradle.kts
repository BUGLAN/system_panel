allprojects {
    repositories {
        // 国内源优先（阿里云镜像）
        maven("https://maven.aliyun.com/repository/google")
        maven("https://maven.aliyun.com/repository/public")
        // 兜底：镜像缺件时回退官方源
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// ⚠️ flutter_live2d 1.0.2 的 android/build.gradle.kts 把 CMake 版本**写死**成 3.10.2，
//    而 Google 已经把它从 SDK 仓库下架（`sdkmanager "cmake;3.10.2"` → Package not found），
//    本机只有 3.22.1 —— 于是 `:flutter_live2d:configureCMakeDebug` 直接失败：
//      [CXX1300] CMake '3.10.2' was not found in SDK, PATH, or by cmake.dir property.
//    `local.properties` 里的 `cmake.dir` **压不过** DSL 里的 `version`（试过了），
//    所以在**我们这边**统一改写子工程的 CMake 版本。
//    ⚠️ 这个块必须在下面 `evaluationDependsOn(":app")` **之前** —— 那个调用会立刻
//       求值 `:app`，之后再注册 afterEvaluate 会报
//       "Cannot run Project.afterEvaluate(Action) when the project is already evaluated"。
//    用反射是为了不往构建脚本里引 AGP 的类（省得再补 buildscript classpath）。
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android") ?: return@afterEvaluate
        runCatching {
            val enb = androidExt.javaClass
                .getMethod("getExternalNativeBuild").invoke(androidExt) ?: return@runCatching
            val cmake = enb.javaClass.getMethod("getCmake").invoke(enb) ?: return@runCatching
            cmake.javaClass
                .getMethod("setVersion", String::class.java)
                .invoke(cmake, "3.22.1")
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
