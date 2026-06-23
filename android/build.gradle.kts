import com.android.build.gradle.BaseExtension

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
    afterEvaluate {
        extensions.findByType(BaseExtension::class.java)?.apply {
            compileSdkVersion(36)
            ndkVersion = "28.2.13676358"
        }
        if (project.name == "agora_rtc_engine") {
            project.dependencies.add("implementation", "androidx.appcompat:appcompat:1.7.0")
            project.dependencies.add("implementation", "androidx.core:core:1.13.1")
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
