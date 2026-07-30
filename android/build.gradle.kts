val localProperties =
    java.util.Properties().apply {
        val file = rootProject.file("local.properties")
        if (file.exists()) file.inputStream().use { input -> this.load(input) }
    }

fun localProperty(key: String, default: String): String = localProperties.getProperty(key) ?: default

allprojects {
    repositories {
        google()
        mavenCentral()
        // SoftPay AppSwitch SDK repository (Nexus). Fill in real SOFTPAY_MAVEN_USERNAME/PASSWORD
        // (Nexus Credentials from Softpay Support) in android/local.properties (gitignored).
        maven {
            url = uri(localProperty("SOFTPAY_MAVEN_URL", "https://nexus.softpay.io/repository/softpay-integrator/"))
            credentials {
                username = localProperty("SOFTPAY_MAVEN_USERNAME", "TODO")
                password = localProperty("SOFTPAY_MAVEN_PASSWORD", "TODO")
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
