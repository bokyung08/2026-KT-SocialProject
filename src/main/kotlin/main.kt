package kt.dinjae.pm_safeline

import io.ktor.server.engine.*
import io.ktor.server.application.*

fun main(args: Array<String>) {
    // Ktor 기동 전에 프로젝트 루트 .env 를 시스템 프로퍼티로 로드(PM_OSM_FILE 등 자동 반영).
    Dotenv.load()
    io.ktor.server.netty.EngineMain.main(args)
}
