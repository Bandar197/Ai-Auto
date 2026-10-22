allprojects {
    repositories {
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
// Some plugins (e.g. universal_ble, flutter_libserialport) declare an older compileSdk, while their
// AndroidX dependencies require 34+. Compile every Android library module against the app's SDK.
// compileSdk only selects the API headers used at build time; minSdk/targetSdk are unchanged.
// Registered before evaluationDependsOn(":app") so the hook exists before any module is evaluated.
val pluginCompileSdk = 36
subprojects {
    afterEvaluate {
        val android = extensions.findByName("android") ?: return@afterEvaluate
        if (!plugins.hasPlugin("com.android.library")) return@afterEvaluate
        val setter = android.javaClass.methods.firstOrNull {
            (it.name == "compileSdkVersion" || it.name == "setCompileSdkVersion") &&
                it.parameterTypes.size == 1 && it.parameterTypes[0] == Int::class.javaPrimitiveType
        }
        setter?.invoke(android, pluginCompileSdk)
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
