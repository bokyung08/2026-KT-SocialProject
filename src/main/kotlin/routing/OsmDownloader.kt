package kt.dinjae.pm_safeline.routing

import org.slf4j.LoggerFactory
import java.io.File
import java.net.URI
import java.net.URLEncoder
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.nio.charset.StandardCharsets
import java.time.Duration

/**
 * OSM 도로망 자동 다운로드 (Overpass API).
 *
 * `PM_OSM_FILE` 이 가리키는 파일이 없을 때, 지정된 bbox 의 도로망(highway + turn
 * restriction)을 Overpass 에서 받아 `.osm` XML 로 저장한다. GraphHopper 는 .osm XML 을
 * 그대로 임포트하므로 별도 변환이 필요 없다. 최초 1회만 받고 이후엔 파일이 존재하므로 건너뛴다.
 */
object OsmDownloader {
    private val log = LoggerFactory.getLogger(javaClass)

    /** 대전 중심부 기본 bbox (W,S,E,N) — 파이썬 패키지와 동일. */
    const val DEFAULT_BBOX = "127.30,36.31,127.43,36.39"

    private val MIRRORS = listOf(
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
        "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
    )

    /**
     * [bbox]("W,S,E,N") 영역 도로망을 받아 [target] 에 저장. 성공 시 true.
     * 여러 미러를 순차 시도한다.
     */
    fun download(target: File, bbox: String): Boolean {
        val p = bbox.split(",").map { it.trim().toDouble() }
        require(p.size == 4) { "OSM bbox 형식은 W,S,E,N 이어야 합니다: $bbox" }
        val (w, s, e, n) = p
        val query = """
            [out:xml][timeout:300];
            (way["highway"]($s,$w,$n,$e);rel["type"="restriction"]($s,$w,$n,$e););
            (._;>;);
            out body;
        """.trimIndent()
        val formBody = "data=" + URLEncoder.encode(query, StandardCharsets.UTF_8)

        target.parentFile?.mkdirs()
        val client = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(30)).build()

        for (url in MIRRORS) {
            val tmp = File(target.absolutePath + ".part")
            try {
                log.info("OSM 자동 다운로드 시도: {} (bbox={})", url, bbox)
                val req = HttpRequest.newBuilder(URI.create(url))
                    .timeout(Duration.ofMinutes(6))
                    .header("Content-Type", "application/x-www-form-urlencoded")
                    .header("User-Agent", "pm-safeline/1.0 (routing server)")
                    .POST(HttpRequest.BodyPublishers.ofString(formBody))
                    .build()
                val resp = client.send(req, HttpResponse.BodyHandlers.ofFile(tmp.toPath()))
                if (resp.statusCode() == 200 && tmp.length() > 10_000) {
                    if (target.exists()) target.delete()
                    if (tmp.renameTo(target)) {
                        log.info("OSM 저장 완료: {} ({} bytes)", target, target.length())
                        return true
                    }
                }
                log.warn("OSM 다운로드 실패 status={} size={}", resp.statusCode(), tmp.length())
            } catch (e: Exception) {
                log.warn("OSM 다운로드 오류({}): {}", url, e.message)
            } finally {
                if (tmp.exists()) tmp.delete()
            }
        }
        log.error("모든 미러에서 OSM 다운로드 실패 (bbox={})", bbox)
        return false
    }
}
