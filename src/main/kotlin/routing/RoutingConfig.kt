package kt.dinjae.pm_safeline.routing

/**
 * GraphHopper 엔진/프로파일 설정. Ktor application.yaml 또는 환경변수에서 주입.
 *
 * @param osmFile      OSM 원본(.osm.pbf) 경로. 최초 실행 시 그래프로 임포트됨(§3.1).
 * @param graphCache   임포트 결과 캐시 디렉토리(재기동 시 재사용).
 * @param profile      프로파일 이름.
 * @param turnCosts    edge-based(turn cost) 탐색 활성화(§2.3 상태확장 대체).
 * @param encodedValues 프로파일이 참조할 인코딩값(CustomModel 표현식에서 사용).
 * @param maxAlternatives 후보 경로 최대 개수(§2.4 k-최단경로).
 */
data class RoutingConfig(
    val osmFile: String,
    val graphCache: String = "graph-cache",
    val profile: String = "pm_bike",
    val turnCosts: Boolean = true,
    val encodedValues: List<String> = DEFAULT_ENCODED_VALUES,
    val maxAlternatives: Int = 3,
) {
    companion object {
        /** CustomModel/전환 페널티가 참조하는 표준 인코딩값. */
        val DEFAULT_ENCODED_VALUES = listOf(
            "road_class",
            "road_class_link",
            "road_access",
            "bike_network",
            "bike_priority",
            "bike_average_speed",
        )
    }
}
