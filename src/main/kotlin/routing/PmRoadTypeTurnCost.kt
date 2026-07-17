package kt.dinjae.pm_safeline.routing

import com.graphhopper.routing.ev.DecimalEncodedValue
import com.graphhopper.routing.ev.EnumEncodedValue
import com.graphhopper.routing.ev.RoadClass
import com.graphhopper.routing.weighting.TurnCostProvider
import com.graphhopper.storage.BaseGraph
import com.graphhopper.util.EdgeIteratorState

/**
 * 도로유형 "전환" 페널티 (PROJECT.md §2.3, §3.2 — w3).
 *
 * 직전에 지나온 엣지의 도로유형과 현재 엣지의 도로유형이 다르면(자전거도로 단절 후
 * 차도 합류 등) 전환 페널티를 부과한다. 이는 직전 상태(prev edge)에 의존하므로
 * 순수 노드 단위 비용으로 표현할 수 없고 — GraphHopper 의 edge-based(turn cost) 탐색이
 * `(node, prev_edge)` 상태 확장을 대신 수행한다(§3.2). 여기서는 그 turn 비용만 정의한다.
 *
 * 주의(§3.3): GraphHopper Java API 플랫폼 타입으로 인한 NPE 방지를 위해 명시적 처리.
 */
class PmRoadTypeTurnCost(
    private val graph: BaseGraph,
    private val roadClassEnc: EnumEncodedValue<RoadClass>,
    private val weights: PmCostWeights,
    /** turn_cost EV(초 단위). OSM turn restriction 등 기존 turn 비용과 합산하기 위함(없으면 null). */
    private val turnCostEnc: DecimalEncodedValue? = null,
) : TurnCostProvider {

    /** 전환 1회를 "초"로 환산하는 스케일. weight 단위와 맞추기 위한 상수(튜닝 대상). */
    private val secondsPerTransition = 20.0

    override fun calcTurnWeight(inEdge: Int, viaNode: Int, outEdge: Int): Double {
        // u-turn / 진입엣지 없음(가상 엣지) 은 페널티 없음.
        if (inEdge == outEdge) return 0.0
        if (inEdge < 0 || outEdge < 0) return 0.0

        val fromClass = roadClassGroup(inEdge)
        val toClass = roadClassGroup(outEdge)

        val base = if (fromClass != toClass) weights.transitionPenalty else 0.0

        // 기존 OSM turn 비용(초) 합산.
        val osmTurn = turnCostEnc?.let { readOsmTurnSeconds(inEdge, viaNode, outEdge, it) } ?: 0.0
        return base + osmTurn
    }

    override fun calcTurnMillis(inEdge: Int, viaNode: Int, outEdge: Int): Long {
        val w = calcTurnWeight(inEdge, viaNode, outEdge)
        if (w.isInfinite()) return Long.MAX_VALUE
        return Math.round(w * secondsPerTransition * 1000.0)
    }

    /** 엣지의 도로유형을 연속성 판단용 그룹으로 축약(자전거도로/차도/보도/기타). */
    private fun roadClassGroup(edge: Int): RoadTypeGroup {
        val state: EdgeIteratorState = graph.getEdgeIteratorState(edge, Int.MIN_VALUE)
        val rc = state.get(roadClassEnc)
        // RoadClass 는 링크(_LINK) 값을 별도로 두지 않는다(road_class_link EV 로 표현).
        return when (rc) {
            RoadClass.CYCLEWAY -> RoadTypeGroup.CYCLE
            RoadClass.MOTORWAY, RoadClass.TRUNK, RoadClass.PRIMARY, RoadClass.SECONDARY,
            RoadClass.TERTIARY, RoadClass.RESIDENTIAL, RoadClass.UNCLASSIFIED,
            RoadClass.SERVICE, RoadClass.ROAD, RoadClass.LIVING_STREET, RoadClass.TRACK -> RoadTypeGroup.ROAD
            RoadClass.FOOTWAY, RoadClass.PEDESTRIAN, RoadClass.PATH, RoadClass.STEPS,
            RoadClass.BRIDLEWAY, RoadClass.CORRIDOR -> RoadTypeGroup.FOOT
            else -> RoadTypeGroup.OTHER
        }
    }

    private fun readOsmTurnSeconds(
        inEdge: Int, viaNode: Int, outEdge: Int, enc: DecimalEncodedValue,
    ): Double {
        val tcs = graph.turnCostStorage ?: return 0.0
        return tcs.get(enc, inEdge, viaNode, outEdge)
    }

    private enum class RoadTypeGroup { CYCLE, ROAD, FOOT, OTHER }

    companion object {
        /** GraphHopper 가 turn cost 없이 라우팅할 때 쓰는 무비용 provider. */
        val NO_TURN_COST: TurnCostProvider = TurnCostProvider.NO_TURN_COST_PROVIDER
    }
}
