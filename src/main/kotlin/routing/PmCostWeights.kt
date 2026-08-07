package kt.dinjae.pm_safeline.routing

import com.graphhopper.json.Statement
import com.graphhopper.json.Statement.Op
import com.graphhopper.util.CustomModel

/**
 * PM 연속주행 안전 경로의 비용함수 가중치 (PROJECT.md §2.2, §4).
 *
 * 비용함수(개념):
 * ```
 * cost(edge) = w1*거리 + w2*차도페널티 + w3*전환페널티 + w4*교차로페널티 + w5*버스겹침페널티
 * ```
 *
 * 이 값들은 IRL(Bradley-Terry) 학습 결과로 주입된다(§4.2). 학습은 오프라인이며,
 * 서비스 탐색 시에는 고정 선형함수라 탐색 속도에 영향 없음(§4.2 주석).
 *
 * GraphHopper CustomModel 매핑(§3.1, docs 공식 공식):
 * ```
 * edge_weight = distance/(speed*priority) + distance*distance_influence + turn_penalty
 * ```
 * - [distanceWeight] (w1)      -> distance_influence (미터당 가중, 클수록 짧은 경로 선호)
 * - [arterialPenalty] (w2)     -> 차도/간선 road_class 에 priority 감쇠
 * - [transitionPenalty] (w3)   -> 직전 도로유형 의존 -> CustomModel 불가 -> [PmRoadTypeTurnCost] 로 처리
 * - [crossingPenalty] (w4)     -> 교차로/횡단보도 성격 엣지에 priority 감쇠
 * - [busOverlapPenalty] (w5)   -> 버스/트램 노선 겹침 엣지에 priority 감쇠(커스텀 EV 필요)
 *
 * priority 감쇠 계수는 penalty(≥0)를 `1/(1+penalty)` 로 사상해 항상 (0,1] 범위의
 * 곱셈 계수가 되도록 한다 -> weight 증가(안전할수록 우대) + 항상 양수 비용 보장.
 */
data class PmCostWeights(
    val distanceWeight: Double = 1.0,
    val arterialPenalty: Double = 3.0,
    val transitionPenalty: Double = 2.0,
    val crossingPenalty: Double = 1.5,
    val busOverlapPenalty: Double = 1.0,
) {
    init {
        require(sequenceOf(distanceWeight, arterialPenalty, transitionPenalty, crossingPenalty, busOverlapPenalty)
            .all { it >= 0.0 }) { "가중치는 음수가 될 수 없습니다(admissibility/양수비용 보장): $this" }
    }

    /** penalty(≥0) -> (0,1] priority 곱셈 계수. */
    private fun factor(penalty: Double): String = (1.0 / (1.0 + penalty)).toString()

    /**
     * 이 가중치를 GraphHopper 질의용 [CustomModel] 로 변환.
     *
     * 기준 엣지 표현식은 표준 인코딩값(road_class, bike_network, road_access)에 의존한다.
     * w3(전환)은 여기 포함되지 않고 [PmRoadTypeTurnCost] 가 담당한다.
     */
    fun toCustomModel(): CustomModel {
        val cm = CustomModel()
        // w1: 거리 영향. GraphHopper distance_influence 단위는 (weight/1000m) 관례라 스케일 반영.
        cm.distanceInfluence = distanceWeight * 70.0

        // w2: 간선/차도 회피 — 자전거도로 연속성(§1.5)을 위해 큰길일수록 감쇠.
        cm.addToPriority(Statement.If("road_class == MOTORWAY || road_class == TRUNK", Op.MULTIPLY, factor(arterialPenalty * 4)))
        cm.addToPriority(Statement.ElseIf("road_class == PRIMARY", Op.MULTIPLY, factor(arterialPenalty * 2)))
        cm.addToPriority(Statement.ElseIf("road_class == SECONDARY", Op.MULTIPLY, factor(arterialPenalty)))

        // 자전거 인프라 우대(연속주행 핵심): 자전거도로/지정 네트워크는 priority 유지·가산.
        cm.addToPriority(Statement.If("road_class == CYCLEWAY", Op.MULTIPLY, "1.0"))
        cm.addToPriority(Statement.If("bike_network != MISSING", Op.MULTIPLY, "1.0"))

        // w4: 교차로/연결로(램프·링크) 성격 엣지에 감쇠. RoadClass 에는 _LINK 값이 없고
        //     링크 여부는 별도 불린 EV road_class_link 로 표현된다(정밀 crossing EV는 커스텀 임포트 필요).
        cm.addToPriority(Statement.If("road_class_link", Op.MULTIPLY, factor(crossingPenalty)))

        // w5: 버스/트램 노선 겹침. 표준 OSM EV 로는 직접 표현 불가 -> 커스텀 EV "bus_overlap" 전제.
        //     해당 EV 임포트 전에는 no-op 이 되도록 방어적으로 주석 처리된 훅.
        //     TODO(§4.5): bus_overlap 커스텀 EncodedValue 임포트 후 아래 활성화.
        // cm.addToPriority(Statement.If("bus_overlap", Op.MULTIPLY, factor(busOverlapPenalty)))

        return cm
    }

    companion object {
        /**
         * 비용함수 = **두 목적의 결합** — docs/results/IRL_REPORT.md (2026-08).
         *
         * (a) **PM 주행 연속성/승차감**(자전거도로 우선·차도 회피). teacher 사고위험과 무관하다
         *     (자전거도로 근접↔위험 corr ~0 실측) → IRL 학습 대상이 아니라 **도메인 값**([bikeContinuity]).
         *     PROJECT §1 의 "자전거도로 이용 비율 / 차도 사용 자제"가 곧 w2.
         * (b) **사고위험 회피** — teacher 로부터 IRL(표준화 nonneg Bradley-Terry, 1,310 지점) 학습:
         *     - **교차로 밀도** (corr +0.43) → 0.486  = w4(주 안전 페널티)
         *     - **전환 다양성**(반경 내 도로유형 종류수, corr +0.35) → 0.266 = w3
         *     - **버스정류장 밀도**(corr +0.29) → 0.272 = w5
         *     전환다양성별 위험: 1종 0.25 / 2종 0.48 / 3종 0.57(전환 잦을수록 위험).
         *
         * [beta] = 안전 강도(위험↔거리 교환율, 정책 파라미터, (b)에만 적용). daejeon/busan/cheongju
         * 검증에서 beta=2 가 경로 거리 +5~10%로 teacher 위험 −8~15% 감소.
         *
         * 발견(미반영, 향후 w6 후보): **편의시설(amenity) 밀도**가 위험과 corr +0.34 로 강하고
         * 기존 인자와 독립적(전환과 corr 0.01) — 상업 밀집지가 사고위험↑. POI 밀도 EV 추가 시 반영 권장.
         *
         * 주의(프록시): IRL 은 '반경 내 밀도/다양성'을 측정했고, 이 CustomModel/turn-cost 는
         * road_class_link(교차로)·road-type turn(전환)·bus_overlap EV(버스)로 근사한다 —
         * **상대비·부호는 유효하나 절대 크기는 프록시·beta 에 의존**.
         */
        fun irlLearned(beta: Double = 2.0, bikeContinuity: Double = 3.0): PmCostWeights = PmCostWeights(
            distanceWeight = 1.0,
            arterialPenalty = bikeContinuity, // (a) 자전거도로 연속성 — 도메인 목적, teacher/IRL 무관
            transitionPenalty = beta * 0.266, // (b) IRL 사고위험: 도로유형 전환(자전거단절 포함)
            crossingPenalty = beta * 0.486,   // (b) IRL 사고위험: 교차로 밀도(주 페널티)
            busOverlapPenalty = beta * 0.272, // (b) IRL 사고위험: 버스 밀도
        )

        /** 안전 우선 기본값 = (a)자전거연속성 + (b)IRL 사고위험(§4.2, beta=2). */
        val SAFE_DEFAULT: PmCostWeights = irlLearned()

        /** 거리 우선(비교/기준선용). */
        val SHORTEST: PmCostWeights = PmCostWeights(
            distanceWeight = 5.0, arterialPenalty = 0.0, transitionPenalty = 0.0,
            crossingPenalty = 0.0, busOverlapPenalty = 0.0,
        )
    }
}
