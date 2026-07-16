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
// `receive_sharing_intent` 1.9.0 hardcodes `compileSdk 37`, which AGP resolves to
// the platform hash `android-37`. That platform does not exist and cannot be
// installed: Google ships `android-37.0` and `android-37.1`, and there is no bare
// `android-37` in the SDK manager at all. So the plugin fails to configure on a
// fully up-to-date SDK, with an error that names a target nobody asked for.
//
// This pins any plugin asking for the missing hash to the newest platform that is
// actually installable. It is safe for this plugin — it targets `minSdk 21` and
// uses nothing newer than the share intent APIs, which have been stable for years
// — and it is scoped to the exact broken value rather than clamping every
// subproject, so a plugin that legitimately needs a newer SDK is left alone and a
// future `receive_sharing_intent` that fixes this upstream stops matching and the
// override quietly stops firing.
//
// Remove when the plugin declares an SDK that exists.
subprojects {
    afterEvaluate {
        val android = project.extensions.findByName("android") ?: return@afterEvaluate

        android.withGroovyBuilder {
            if ("getCompileSdkVersion"() == "android-37") {
                "compileSdkVersion"("android-36")
            }
        }
    }
}

// Must stay *after* the override above: this forces every subproject to evaluate,
// and an `afterEvaluate` registered on an already-evaluated project throws.
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
