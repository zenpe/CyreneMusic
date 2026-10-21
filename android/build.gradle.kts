import org.gradle.api.tasks.compile.JavaCompile
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

// Opt-in task timings for the release script. No global Gradle init script or
// changes to the task graph are needed.
if (providers.gradleProperty("cyreneBuildTimingFile").isPresent) {
    apply(from = "../scripts/gradle-build-timing.gradle")
}

allprojects {
    repositories {
        // 阿里云镜像（加速国内下载）
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://maven.aliyun.com/repository/central") }
        
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    // Apply the same repositories to plugin buildscript dependencies. Hosted
    // plugins may declare their own AGP classpath before project repositories
    // apply; keep those downloads on the existing mirror-first policy too.
    buildscript.repositories {
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        google()
        mavenCentral()
    }
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    // Kotlin incremental caches cannot relativize sources and outputs on
    // different Windows drives. Retain that workaround only where necessary.
    if (project.projectDir.toPath().root != newBuildDir.asFile.toPath().root) {
        tasks.withType<KotlinCompile>().configureEach {
            incremental = false
        }
    }

    configurations.configureEach {
        resolutionStrategy {
            // home_widget 0.9.0 declares Glance as 1.+, which can select
            // alpha releases requiring a newer AGP than Flutter supports.
            force("androidx.glance:glance-appwidget:1.1.1")
            force("androidx.glance:glance:1.1.1")
        }
    }
}

gradle.projectsEvaluated {
    subprojects.filter { it.name == "home_widget" }.forEach {
        it.tasks.withType<JavaCompile>().configureEach {
            sourceCompatibility = JavaVersion.VERSION_11.toString()
            targetCompatibility = JavaVersion.VERSION_11.toString()
        }

        it.tasks.withType<KotlinJvmCompile>().configureEach {
            compilerOptions.jvmTarget.set(JvmTarget.JVM_11)
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
