package kt.dinjae.pm_safeline.plugins

import io.ktor.http.HttpHeaders
import io.ktor.http.HttpMethod
import io.ktor.server.application.Application
import io.ktor.server.application.install
import io.ktor.server.plugins.cors.routing.CORS

private val localDevelopmentOrigin = Regex("""^https?://(?:localhost|127\.0\.0\.1)(?::\d+)?$""")

/** Flutter Web 로컬 개발 서버에서 API를 호출할 수 있도록 제한된 CORS를 설정한다. */
fun Application.configureCors() {
    install(CORS) {
        allowOrigins { origin -> localDevelopmentOrigin.matches(origin) }
        allowMethod(HttpMethod.Get)
        allowMethod(HttpMethod.Post)
        allowMethod(HttpMethod.Options)
        allowHeader(HttpHeaders.ContentType)
        allowHeader(HttpHeaders.Accept)
        // 현재 프로토타입은 인증 쿠키를 사용하지 않는다.
        allowCredentials = false
        maxAgeInSeconds = 3600
    }
}