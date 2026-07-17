package kt.dinjae.pm_safeline

import io.ktor.server.application.*
import io.ktor.server.plugins.openapi.*
import io.ktor.server.routing.*
import io.ktor.server.plugins.swagger.*

fun Application.configureHttp() {
    routing {
        // 정적 API 문서(ReDoc, /openapi) + 인터랙티브 Swagger UI(/swagger). 둘 다 documentation.yaml 사용.
        openAPI(path = "openapi", swaggerFile = "documentation.yaml")
        swaggerUI(path = "swagger", swaggerFile = "documentation.yaml")
    }
}
