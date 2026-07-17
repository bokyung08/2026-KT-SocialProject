package kt.dinjae.pm_safeline

import java.io.File

/**
 * 의존성 없는 경량 `.env` 로더 (python 쪽 pm_safeline.utils.config 와 동일 개념).
 *
 * JVM 서버는 OS 환경변수만 읽고 `.env` 는 자동으로 읽지 않으므로, 기동 시 프로젝트
 * 루트의 `.env` 를 읽어 **시스템 프로퍼티**로 주입한다. 이렇게 하면 `./gradlew run`
 * 만으로 PM_OSM_FILE 등이 반영된다.
 *
 * 규칙:
 * - `KEY=VALUE` 형식, `#` 주석·빈 줄 무시, 양끝 따옴표 제거.
 * - 이미 실제 환경변수나 시스템 프로퍼티로 설정된 키는 덮어쓰지 않는다(실값 우선).
 * - CWD 에서 위로 최대 5단계까지 `.env` 를 탐색.
 */
object Dotenv {

    /** 로드된 값 조회(시스템 프로퍼티 → 환경변수 순). 미설정 시 null. */
    fun get(key: String): String? =
        System.getProperty(key)?.takeIf { it.isNotBlank() }
            ?: System.getenv(key)?.takeIf { it.isNotBlank() }

    fun load() {
        val file = findDotenv() ?: return
        file.readLines().forEach { raw ->
            val line = raw.trim()
            if (line.isEmpty() || line.startsWith("#") || "=" !in line) return@forEach
            val key = line.substringBefore("=").trim()
            var value = line.substringAfter("=").trim()
            if (value.length >= 2 &&
                ((value.startsWith("\"") && value.endsWith("\"")) ||
                    (value.startsWith("'") && value.endsWith("'")))
            ) {
                value = value.substring(1, value.length - 1)
            }
            if (key.isNotEmpty() && System.getProperty(key) == null && System.getenv(key) == null) {
                System.setProperty(key, value)
            }
        }
    }

    private fun findDotenv(): File? {
        var dir: File? = File(System.getProperty("user.dir"))
        repeat(5) {
            val f = dir?.resolve(".env")
            if (f != null && f.isFile) return f
            dir = dir?.parentFile
        }
        return null
    }
}
