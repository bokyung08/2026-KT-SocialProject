plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
    alias(ktorLibs.plugins.ktor)
}

group = "kt.dinjae.pm_safeline"
version = "1.0.0-SNAPSHOT"

application {
    mainClass = "io.ktor.server.netty.EngineMain"
}

kotlin {
    jvmToolchain(21)
}

// --- Windows + 비-ASCII(한글) 프로젝트 경로 회피책 ---------------------------------
// 근본 원인: `./gradlew test`가 테스트 워커 JVM을 띄울 때, 클래스패스가 길면 Gradle이
// 그 내용을 임시 "@argfile"(예: gradle-worker-classpathNNN.txt)에 적어 `java @file` 형태로
// 넘긴다. 이 argfile은 Gradle이 JVM 기본 문자셋(JDK18+ JEP 400으로 인해 file.encoding=UTF-8)
// 으로 "쓰지만", java.exe 런처는 OS 로캘 인코딩(이 환경은 sun.jnu.encoding=MS949)으로 그
// 파일을 "읽는다". 두 인코딩이 다르면 비-ASCII 바이트가 깨져서 해당 경로의 클래스패스 항목이
// 통째로 무효화되고, 그 경로 아래 있는 컴파일된 테스트 클래스가 로드되지 않아
// `ClassNotFoundException: kt.dinjae.pm_safeline.ServerTest`가 발생한다.
// (java -cp @argfile 로 직접 재현: UTF-8로 쓴 argfile은 실패, 같은 내용을 CP949로 다시
//  인코딩한 argfile은 성공 — JDK/Gradle의 알려진 Windows 제약이며 테스트 코드 문제가 아님)
// org.gradle.jvmargs=-Dsun.jnu.encoding=UTF-8 (gradle.properties)로는 고쳐지지 않는다:
// sun.jnu.encoding은 네이티브 런처가 argfile을 읽기 이전, OS 로캘로 이미 고정되기 때문이다.
// 회피책: 프로젝트 절대 경로에 비-ASCII 문자가 있을 때만, 클래스패스에 오르는 빌드 산출물
// 디렉터리(build/classes/...)를 ASCII 전용 경로(TEMP 하위)로 옮겨 argfile에 비-ASCII
// 바이트가 아예 섞이지 않게 한다. src/ 나 테스트 코드는 건드리지 않는다.
if (Regex("[^\\x00-\\x7F]").containsMatchIn(project.projectDir.absolutePath)) {
    val asciiBuildDir = File(System.getenv("TEMP") ?: System.getProperty("java.io.tmpdir"), "gradle-build-${rootProject.name}")
    layout.buildDirectory.set(asciiBuildDir)
}

tasks.test {
    useJUnitPlatform()
}

// GraphHopper 10 은 deprecated 필드 PropertyNamingStrategy.SNAKE_CASE 를 쓰는데,
// Ktor openapi/swagger 가 끌어오는 최신 Jackson(2.21)에서는 이 필드가 제거되어
// 런타임 NoSuchFieldError 발생. GraphHopper 가 요청하는 2.17.2 로 강제 고정한다.
configurations.all {
    resolutionStrategy {
        force(
            "com.fasterxml.jackson.core:jackson-databind:2.17.2",
            "com.fasterxml.jackson.core:jackson-core:2.17.2",
            "com.fasterxml.jackson.core:jackson-annotations:2.17.2",
        )
    }
}

dependencies {
    implementation(ktorLibs.server.config.yaml)
    implementation(ktorLibs.server.core)
    implementation(ktorLibs.server.netty)
    implementation(ktorLibs.server.openapi)
    implementation(ktorLibs.server.routingOpenapi)
    implementation(ktorLibs.server.swagger)
    implementation(ktorLibs.server.contentNegotiation)
    implementation(ktorLibs.server.statusPages)
    implementation(ktorLibs.serialization.kotlinx.json)
    implementation(libs.logback.classic)

    // 경로 탐색 엔진 (PROJECT.md §3)
    implementation(libs.graphhopper.core)

    testImplementation(kotlin("test"))
    testImplementation(ktorLibs.server.testHost)
}
