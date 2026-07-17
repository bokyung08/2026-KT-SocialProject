package kt.dinjae.pm_safeline.api

import kotlinx.serialization.Serializable

/** 경로 탐색 요청. 출발/목적 좌표 + 선택적 가중치 오버라이드. */
@Serializable
data class RouteRequest(
    val fromLat: Double,
    val fromLon: Double,
    val toLat: Double,
    val toLon: Double,
    /** null 이면 서버 기본(IRL 학습) 가중치 사용. */
    val weights: WeightsDto? = null,
    /** 반환할 후보 경로 수(§2.4). null 이면 설정 기본값. */
    val alternatives: Int? = null,
)

/** 비용함수 가중치 DTO (PmCostWeights 미러). */
@Serializable
data class WeightsDto(
    val distanceWeight: Double = 1.0,
    val arterialPenalty: Double = 3.0,
    val transitionPenalty: Double = 2.0,
    val crossingPenalty: Double = 1.5,
    val busOverlapPenalty: Double = 1.0,
)

/** 경로 탐색 응답: 후보 경로 목록(안전점수 내림차순 아님, 비용 오름차순). */
@Serializable
data class RouteResponse(
    val routes: List<RouteDto>,
)

/** 단일 후보 경로. */
@Serializable
data class RouteDto(
    val distanceMeters: Double,
    val durationMillis: Long,
    /** 스칼라 탐색 비용(§2.2). 낮을수록 우선. */
    val weight: Double,
    /** 연속주행 안전 점수(0~100, 높을수록 안전, §1.4). */
    val safetyScore: Double,
    /** [lon, lat] 좌표열(GeoJSON 관례). */
    val geometry: List<List<Double>>,
    /** 경로 진단 지표(§1.4 경로별 비교용). */
    val metrics: RouteMetrics,
)

/** 경로별 연속성/위험 진단 지표. */
@Serializable
data class RouteMetrics(
    /** 자전거도로 이용 비율(0~1). */
    val bikeInfraRatio: Double,
    /** 도로유형 전환 횟수(자전거도로 단절/차도 합류). */
    val transitionCount: Int,
)

/** 헬스체크 응답. */
@Serializable
data class HealthResponse(val status: String, val engine: Boolean)

/** 에러 응답. */
@Serializable
data class ErrorResponse(val error: String, val detail: String? = null)
