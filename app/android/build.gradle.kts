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
// Every plugin module compiles against API 36.
//
// flutter_plugin_android_lifecycle (a transitive dependency of image_picker and
// file_picker) publishes AAR metadata demanding 36, while file_picker pins
// itself to 34 in its own build file -- so `:file_picker` fails its AAR
// metadata check before any of our code is compiled. Raising compileSdk on the
// app module does not help: the check runs per module.
//
// `afterEvaluate` is required, not stylistic: the plugin's own build file sets
// compileSdk during evaluation, and anything set earlier is overwritten.
subprojects {
    afterEvaluate {
        val android = extensions.findByName("android")
        if (android is com.android.build.gradle.BaseExtension) {
            android.compileSdkVersion(36)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
