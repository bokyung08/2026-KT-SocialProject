package kt.dinjae.traffic

import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.http.content.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import kt.dinjae.traffic.api.ErrorResponse
import kt.dinjae.traffic.api.HealthResponse
import kt.dinjae.traffic.api.RouteRequest
import kt.dinjae.traffic.routing.PmCostWeights
import kt.dinjae.traffic.routing.RoutingModule

/**
 * 라우팅 서브시스템을 구성하고 REST 엔드포인트를 등록한다.
 *
 * - `GET  /health`         상태 확인(엔진 로드 여부 포함)
 * - `POST /route`          경로 탐색(§1.4, §2.4). 본문 [RouteRequest].
 *
 * [RoutingModule] 은 앱 시작 시 1회 생성되고 종료 시 닫힌다.
 */
fun Application.configureRouting() {
    val module = RoutingModule.from(environment.config)
    monitor.subscribe(ApplicationStopping) { module.close() }

    routing {
        // 테스트 클라이언트 페이지: src/main/resources/static/ 를 정적 서빙(/ -> index.html).
        staticResources("/", "static", index = "index.html")

        get("/health") {
            call.respond(HealthResponse(status = "ok", engine = module.routeService != null))
        }

        post("/route") {
            val service = module.routeService
                ?: return@post call.respond(
                    HttpStatusCode.ServiceUnavailable,
                    ErrorResponse("engine_unavailable", "routing.osmFile 미설정으로 엔진이 비활성 상태입니다."),
                )

            val req = call.receive<RouteRequest>()
            val weights = req.weights?.let {
                PmCostWeights(
                    distanceWeight = it.distanceWeight,
                    arterialPenalty = it.arterialPenalty,
                    transitionPenalty = it.transitionPenalty,
                    crossingPenalty = it.crossingPenalty,
                    busOverlapPenalty = it.busOverlapPenalty,
                )
            } ?: module.defaultWeights

            val response = service.route(
                req.fromLat, req.fromLon, req.toLat, req.toLon, weights, req.alternatives,
            )
            call.respond(response)
        }
    }
}
