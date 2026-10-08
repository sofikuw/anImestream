import org.jetbrains.kotlin.gradle.dsl.JvmTarget

group = "com.jhomlala.better_player"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.1.0"
    
    repositories {
        google()
        mavenCentral()
    }

    val agpMajor = com.android.Version.ANDROID_GRADLE_PLUGIN_VERSION.substringBefore('.').toInt()

    if (agpMajor < 9) {
        apply(plugin = "org.jetbrains.kotlin.android")
    }

    dependencies {
        // classpath("com.android.tools.build:gradle:8.7.0")
        // classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

val media3Version = "1.8.0"
val lifecycleVersion = "2.4.0-beta01"
val annotationVersion = "1.2.0"
val workVersion = "2.7.0"

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_11) 
    }
}

android {
    namespace = "com.jhomlala.better_player"
    compileSdk = 37

    defaultConfig {
        minSdk = 21
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    sourceSets {
        getByName("main") {
            java.srcDir("src/main/kotlin")
        }
        getByName("test") {
            java.srcDir("src/test/kotlin")
        }
    }

    testOptions {
        unitTests.all {
            it.useJUnitPlatform()

            it.testLogging {
                events(
                    "passed",
                    "skipped",
                    "failed",
                    "standardOut",
                    "standardError"
                )
                showStandardStreams = true
            }

            it.outputs.upToDateWhen { false }
        }
    }
}

dependencies {
    implementation("androidx.media3:media3-exoplayer:$media3Version")
    implementation("androidx.media3:media3-exoplayer-hls:$media3Version")
    implementation("androidx.media3:media3-exoplayer-dash:$media3Version")
    implementation("androidx.media3:media3-exoplayer-smoothstreaming:$media3Version")
    implementation("androidx.media3:media3-datasource-okhttp:$media3Version")
    implementation("androidx.media3:media3-ui:$media3Version")
    implementation("androidx.media3:media3-session:$media3Version")

    // implementation("androidx.media:media:1.7.1")

    implementation("androidx.lifecycle:lifecycle-runtime-ktx:$lifecycleVersion")
    implementation("androidx.lifecycle:lifecycle-common:$lifecycleVersion")
    implementation("androidx.lifecycle:lifecycle-common-java8:$lifecycleVersion")
    implementation("androidx.annotation:annotation:$annotationVersion")
    implementation("androidx.work:work-runtime:$workVersion")

    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.mockito:mockito-core:5.0.0")
}