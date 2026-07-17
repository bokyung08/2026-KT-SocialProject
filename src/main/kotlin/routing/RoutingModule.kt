package kt.dinjae.pm_safeline.routing

import io.ktor.server.config.ApplicationConfig
import io.ktor.server.config.tryGetString
import kt.dinjae.pm_safeline.Dotenv
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
            // 우선순위: application.yaml(${?ENV}) → .env/시스템 프로퍼티/환경변수(Dotenv).
            fun resolve(key: String, env: String): String? =
                config.tryGetString(key)?.takeIf { it.isNotBlank() } ?: Dotenv.get(env)

            val osmFile = resolve("routing.osmFile", "PM_OSM_FILE")
            val weights = PmCostWeights.SAFE_DEFAULT

            if (osmFile.isNullOrBlank()) {
                log.warn("routing.osmFile(PM_OSM_FILE) 미설정 -> 엔진 비활성. /route 는 503 을 반환합니다.")
                return RoutingModule(null, null, weights)
            }

            // OSM 파일이 없으면 Overpass 에서 자동 다운로드(최초 1회). 서버에선 .env 만 있으면 됨.
            val osm = File(osmFile)
            if (!osm.exists()) {
                val auto = resolve("routing.osmAutoDownload", "PM_OSM_AUTODOWNLOAD")?.toBoolean() ?: true
                val bbox = resolve("routing.osmBbox", "PM_OSM_BBOX") ?: OsmDownloader.DEFAULT_BBOX
                if (!auto) {
                    log.warn("OSM 파일 없음('{}'), 자동 다운로드 비활성 -> 엔진 비활성.", osmFile)
                    return RoutingModule(null, null, weights)
                }
                log.info("OSM 파일 없음('{}') -> 자동 다운로드 시작(bbox={}). 최초 실행은 수 분 걸릴 수 있습니다.", osmFile, bbox)
                if (!OsmDownloader.download(osm, bbox)) {
                    log.warn("OSM 자동 다운로드 실패 -> 엔진 비활성. /route 는 503 을 반환합니다.")
                    return RoutingModule(null, null, weights)
                }
            }

            val cfg = RoutingConfig(
                osmFile = osmFile,
                graphCache = resolve("routing.graphCache", "PM_GRAPH_CACHE") ?: "graph-cache",
                profile = resolve("routing.profile", "PM_PROFILE") ?: "pm_bike",
                turnCosts = resolve("routing.turnCosts", "PM_TURN_COSTS")?.toBoolean() ?: true,
                maxAlternatives = resolve("routing.maxAlternatives", "PM_MAX_ALTERNATIVES")?.toInt() ?: 3,
            )
            val engine = GraphHopperEngine(cfg).start()
            return RoutingModule(RouteService(engine), engine, weights)
        }
    }
}
