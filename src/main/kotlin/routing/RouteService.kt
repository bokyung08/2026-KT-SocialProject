package kt.dinjae.traffic.routing

import com.graphhopper.GHRequest
import com.graphhopper.GHResponse
import com.graphhopper.ResponsePath
import com.graphhopper.util.DistanceCalcEarth
import com.graphhopper.util.Parameters
import com.graphhopper.util.details.PathDetail
import kt.dinjae.traffic.api.RouteDto
import kt.dinjae.traffic.api.RouteMetrics
import kt.dinjae.traffic.api.RouteResponse
import org.slf4j.LoggerFactory

/**
 * 경로 탐색 서비스 (PROJECT.md §2.4 복수 후보 + §1.4 안전점수).
 *
 * 1) 단일 스칼라 비용함수(CustomModel = 거리+도로유형 페널티) 기준 k-최단경로 후보 생성.
 * 2) 후보별 안전점수/연속성 지표를 산출해 비교 가능하게 반환.
 *
 * GraphHopper 의 alternative_route 알고리즘으로 top-k 를 뽑는다(§2.4 Yen 계열 대체).
 */
class RouteService(private val engine: GraphHopperEngine) {
    private val log = LoggerFactory.getLogger(javaClass)

    companion object {
        private const val ROAD_CLASS_DETAIL = "road_class"
    }

    fun route(
        fromLat: Double, fromLon: Double, toLat: Double, toLon: Double,
        weights: PmCostWeights, alternatives: Int?,
    ): RouteResponse {
        val k = (alternatives ?: engine.maxAlternatives).coerceIn(1, 10)

        val req = GHRequest(fromLat, fromLon, toLat, toLon).apply {
            profile = engine.profileName
            customModel = weights.toCustomModel()
            if (k > 1) {
                algorithm = Parameters.Algorithms.ALT_ROUTE
                putHint(Parameters.Algorithms.AltRoute.MAX_PATHS, k)
            }
            try {
                setPathDetails(listOf(ROAD_CLASS_DETAIL))
            } catch (e: Exception) {
                log.warn("road_class path detail unavailable: {}", e.message)
            }
        }

        val rsp: GHResponse = engine.hopper.route(req)
        if (rsp.hasErrors()) {
            throw RoutingException(rsp.errors.joinToString("; ") { it.message ?: it.toString() })
        }

        val routes = rsp.all.map { toDto(it) }
        return RouteResponse(routes = routes)
    }

    private fun toDto(path: ResponsePath): RouteDto {
        val metrics = computeMetrics(path)
        return RouteDto(
            distanceMeters = path.distance,
            durationMillis = path.time,
            weight = path.routeWeight,
            safetyScore = safetyScore(metrics),
            geometry = path.points.map { listOf(it.lon, it.lat) },
            metrics = metrics,
        )
    }

    /**
     * 연속성/위험 지표 산출: GraphHopper의 "road_class" path detail을 이용해
     * 구간별 도로유형을 구하고, 구간 거리(대권거리 합)로 자전거도로 비율을,
     * 인접 구간 그룹 변화 횟수로 전환수를 계산한다.
     */
    private fun computeMetrics(path: ResponsePath): RouteMetrics {
        val details: List<PathDetail> = path.pathDetails[ROAD_CLASS_DETAIL] ?: emptyList()
        val totalDistance = path.distance
        if (details.isEmpty() || totalDistance <= 0.0) {
            return RouteMetrics(bikeInfraRatio = 0.0, transitionCount = 0)
        }

        val points = path.points
        var bikeDistance = 0.0
        val groups = mutableListOf<RoadGroup>()

        for (detail in details) {
            val segmentDistance = segmentDistance(points, detail.first, detail.last)
            val roadClass = detail.value?.toString()?.lowercase()
            if (roadClass == "cycleway") {
                bikeDistance += segmentDistance
            }
            val group = roadGroupOf(roadClass) ?: continue
            groups.add(group)
        }

        val bikeInfraRatio = (bikeDistance / totalDistance).coerceIn(0.0, 1.0)

        var transitionCount = 0
        for (i in 1 until groups.size) {
            if (groups[i] != groups[i - 1]) transitionCount++
        }

        return RouteMetrics(
            bikeInfraRatio = bikeInfraRatio,
            transitionCount = transitionCount,
        )
    }

    private fun segmentDistance(points: com.graphhopper.util.PointList, first: Int, last: Int): Double {
        if (last <= first) return 0.0
        var dist = 0.0
        for (i in first until last) {
            dist += DistanceCalcEarth.DIST_EARTH.calcDist(
                points.getLat(i), points.getLon(i),
                points.getLat(i + 1), points.getLon(i + 1),
            )
        }
        return dist
    }

    private fun roadGroupOf(roadClass: String?): RoadGroup? {
        if (roadClass.isNullOrBlank() || roadClass == "missing" || roadClass == "other") return null
        return when (roadClass) {
            "cycleway" -> RoadGroup.CYCLE
            "footway", "pedestrian", "path", "steps", "bridleway", "corridor" -> RoadGroup.FOOT
            else -> RoadGroup.ROAD
        }
    }

    private enum class RoadGroup { CYCLE, FOOT, ROAD }

    /** 안전점수(0~100): 전환 적고 자전거도로 비율 높을수록 높음(§1.4). 임시 공식. */
    private fun safetyScore(m: RouteMetrics): Double {
        val base = 100.0 * m.bikeInfraRatio
        val penalty = m.transitionCount * 5.0
        return (base - penalty).coerceIn(0.0, 100.0)
    }
}

class RoutingException(message: String) : RuntimeException(message)
