package kt.dinjae.traffic.routing

import com.graphhopper.GraphHopper
import com.graphhopper.config.Profile
import com.graphhopper.util.CustomModel
import com.graphhopper.util.TurnCostsConfig
import org.slf4j.LoggerFactory
import java.io.Closeable

/**
 * GraphHopper 엔진 수명주기 관리 (PROJECT.md §3).
 *
 * 최초 실행 시 [RoutingConfig.osmFile] 을 그래프로 임포트하고, 이후엔
 * [RoutingConfig.graphCache] 에서 로드한다. turn cost 를 켜면 edge-based 탐색으로
 * `(node, prev_edge)` 상태확장이 인프라 레벨에서 처리된다(§3.2).
 *
 * 프로토타입/가중치 튜닝 단계에서는 CH/LM 없이 flexible 모드로 두어 런타임
 * CustomModel 변경 자유도를 최대화한다(§3.4). 가중치 안정화 후 CH/LM 전환 권장.
 */
class GraphHopperEngine(private val config: RoutingConfig) : Closeable {
    private val log = LoggerFactory.getLogger(javaClass)

    private var _hopper: GraphHopper? = null
    val hopper: GraphHopper
        get() = _hopper ?: error("GraphHopperEngine 이 아직 start() 되지 않았습니다.")

    val profileName: String get() = config.profile
    val maxAlternatives: Int get() = config.maxAlternatives

    fun start(): GraphHopperEngine {
        log.info("GraphHopper 초기화: osm={} cache={} profile={}", config.osmFile, config.graphCache, config.profile)
        val gh = GraphHopper()
        gh.osmFile = config.osmFile
        gh.graphHopperLocation = config.graphCache
        gh.setEncodedValuesString(config.encodedValues.joinToString(","))

        val profile = Profile(config.profile).apply {
            // flexible 모드: 질의 시점 CustomModel 주입을 허용(§3.4).
            customModel = baseCustomModel()
            // turn cost 활성화 시 edge-based 탐색으로 (node, prev_edge) 상태확장 처리(§3.2).
            if (config.turnCosts) setTurnCostsConfig(TurnCostsConfig.bike())
        }
        gh.setProfiles(profile)
        gh.importOrLoad()
        _hopper = gh
        log.info("GraphHopper 준비 완료.")
        return this
    }

    /**
     * 프로파일 기본 CustomModel. bike 속도 인코딩값을 참조해 자전거 관점 속도를 부여한다.
     * 질의 시점에 [PmCostWeights.toCustomModel] 이 이 위에 병합된다.
     */
    private fun baseCustomModel(): CustomModel {
        return CustomModel().apply {
            // bike_average_speed 를 기준 속도로 사용(자전거/PM 관점).
            addToSpeed(com.graphhopper.json.Statement.If("true", com.graphhopper.json.Statement.Op.LIMIT, "bike_average_speed"))
            addToPriority(com.graphhopper.json.Statement.If("bike_priority > 0", com.graphhopper.json.Statement.Op.MULTIPLY, "bike_priority"))
        }
    }

    override fun close() {
        _hopper?.close()
        _hopper = null
        log.info("GraphHopper 종료.")
    }
}
