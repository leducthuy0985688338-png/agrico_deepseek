import com.android.build.gradle.BaseExtension

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.buildDir = File(rootProject.projectDir, "../build")

subprojects {
    project.buildDir = File(rootProject.buildDir, "${project.name}")
}

subprojects {
    project.evaluationDependsOn(":app")

    afterEvaluate {
        extensions.findByType(BaseExtension::class.java)?.compileSdkVersion(36)
    }
}

tasks.register("clean", Delete::class) {
    delete(rootProject.buildDir)
}
