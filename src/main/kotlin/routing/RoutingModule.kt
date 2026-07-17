package kt.dinjae.traffic.routing

import io.ktor.server.config.ApplicationConfig
import io.ktor.server.config.tryGetString
import org.slf4j.LoggerFactory
import java.io.File

/**
 * 라우팅 서브시스템 컴포지션 루트(경량 DI).
 *
 * application.yaml 의 `routing` 섹션을 읽어 [GraphHopperEngine] 과 [RouteService] 를 구성한다.
 * OSM 파일이 없거나 미설정이면 엔진을 시작하지 않고 [routeService] 를 null 로 둔다
 * (서버는 정상 기동, /route 호출 시에만 503). 개발/테스트 편의.
 */
class RoutingModule private constructor(
    val routeService: RouteService?,
    private val engine: GraphHopperEngine?,
    val defaultWeights: PmCostWeights,
) {
    fun close() = engine?.close()

    companion object {
        private val log = LoggerFactory.getLogger(RoutingModule::class.java)

        fun from(config: ApplicationConfig): RoutingModule {
            val osmFile = config.tryGetString("routing.osmFile")
            val weights = PmCostWeights.SAFE_DEFAULT

            if (osmFile.isNullOrBlank() || !File(osmFile).exists()) {
                log.warn("routing.osmFile 미설정 또는 파일 없음('{}') -> 엔진 비활성. /route 는 503 을 반환합니다.", osmFile)
                return RoutingModule(null, null, weights)
            }

            val cfg = RoutingConfig(
                osmFile = osmFile,
                graphCache = config.tryGetString("routing.graphCache") ?: "graph-cache",
                profile = config.tryGetString("routing.profile") ?: "pm_bike",
                turnCosts = config.tryGetString("routing.turnCosts")?.toBoolean() ?: true,
                maxAlternatives = config.tryGetString("routing.maxAlternatives")?.toInt() ?: 3,
            )
            val engine = GraphHopperEngine(cfg).start()
            return RoutingModule(RouteService(engine), engine, weights)
        }
    }
}
