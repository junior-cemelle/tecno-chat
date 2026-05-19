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
subprojects {
    project.evaluationDependsOn(":app")
}

// Parche: plugins antiguos sin namespace (requerido por AGP 8+).
subprojects {
    pluginManager.withPlugin("com.android.library") {
        extensions
            .findByType(com.android.build.gradle.LibraryExtension::class.java)
            ?.takeIf { it.namespace == null }
            ?.apply {
                val grp = project.group.toString()
                namespace = if (grp.isNotBlank()) grp
                            else "com.plugin.${project.name.replace("-", "_")}"
            }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
