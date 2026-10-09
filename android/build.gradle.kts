allprojects {
    repositories {
        google()
        mavenCentral()
        // Repo Maven locale del SDK Brother: il plugin brother_native_print
        // pubblica l'AAR ufficiale nel proprio android/maven-repo (vedi README
        // del plugin, sezione Android). La dipendenza transitiva si risolve
        // con i repository del PROGETTO OSPITE: si cerca il plugin nel pub
        // cache (variabile PUB_CACHE o percorsi predefiniti Windows/Unix).
        val pubCacheCandidates = listOfNotNull(
            System.getenv("PUB_CACHE")?.let { "$it/hosted/pub.dev" },
            "${System.getProperty("user.home")}/AppData/Local/Pub/Cache/hosted/pub.dev",
            "${System.getProperty("user.home")}/.pub-cache/hosted/pub.dev",
        )
        for (base in pubCacheCandidates) {
            val brotherRepo = File(base)
                .listFiles { file -> file.name.startsWith("brother_native_print-") }
                ?.maxByOrNull { it.name }
                ?.resolve("android/maven-repo")
            if (brotherRepo?.isDirectory == true) {
                maven { url = uri(brotherRepo) }
                logger.lifecycle("SDK Brother: repo Maven da ${brotherRepo.path}")
                break
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
    val newSubprojectBuildDir = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
