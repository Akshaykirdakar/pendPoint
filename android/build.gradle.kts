import com.android.build.gradle.BaseExtension

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Some Flutter plugins (e.g. blue_thermal_printer, last published years ago)
// predate AGP's namespace requirement and don't declare one in their own
// build.gradle, which fails the build under modern AGP (8.x). Patch a
// namespace onto any such subproject rather than forking the plugin.
subprojects {
    afterEvaluate {
        extensions.findByType(BaseExtension::class.java)?.let { android ->
            if (android.namespace == null) {
                android.namespace = "com.pendpoint.plugins.${project.name.replace('-', '_')}"
            }
        }
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
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
