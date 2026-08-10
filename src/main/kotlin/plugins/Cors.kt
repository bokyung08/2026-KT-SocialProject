package kt.dinjae.pm_safeline.plugins

import io.ktor.http.HttpHeaders
import io.ktor.http.HttpMethod
import io.ktor.server.application.Application
import io.ktor.server.application.install
import io.ktor.server.plugins.cors.routing.CORS

private val localDevelopmentOrigin = Regex("""^https?://(?:localhost|127\.0\.0\.1)(?::\d+)?$""")
private val productionOrigin = Regex("""^https://gilit\.thisisthepy\.org$""")
private val tossMiniAppOrigin = Regex("""^https://pmsafeline\.(?:private-)?(?:web|apps)\.tossmini\.com$""")

/** Flutter Web 로컬 개발 서버 + 배포 도메인 + 토스 미니앱(pmsafeline, 실서비스/QR테스트)에서 API를 호출할 수 있도록 제한된 CORS를 설정한다. */
fun Application.configureCors() {
    install(CORS) {
        allowOrigins { origin ->
            localDevelopmentOrigin.matches(origin) ||
                productionOrigin.matches(origin) ||
                tossMiniAppOrigin.matches(origin)
        }
        allowMethod(HttpMethod.Get)
        allowMethod(HttpMethod.Post)
        allowMethod(HttpMethod.Options)
        allowHeader(HttpHeaders.ContentType)
        allowHeader(HttpHeaders.Accept)
        allowCredentials = false
        maxAgeInSeconds = 3600
    }
}
