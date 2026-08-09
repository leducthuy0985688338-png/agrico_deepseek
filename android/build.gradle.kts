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
}

tasks.register("clean", Delete::class) {
    delete(rootProject.buildDir)
}
