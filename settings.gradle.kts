pluginManagement {
    repositories {
        google()
        gradlePluginPortal()
        mavenCentral()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "TripPals"

include(":shared")
include(":androidApp")

project(":shared").projectDir = file("apps/mobile/shared")
project(":androidApp").projectDir = file("apps/mobile/androidApp")
