package kt.dinjae.traffic

import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import io.ktor.server.testing.*
import kt.dinjae.traffic.plugins.configureSerialization
import kt.dinjae.traffic.plugins.configureStatusPages
import kotlin.test.*

class ServerTest {

    /** 라우팅 엔진 없이도(osmFile 미설정) 서버가 기동되고 /health 가 응답하는지. */
    @Test
    fun healthEndpointRespondsOk() = testApplication {
        application {
            configureSerialization()
            configureStatusPages()
            configureRouting()
        }
        val resp = client.get("/health")
        assertEquals(HttpStatusCode.OK, resp.status)
        assertTrue(resp.bodyAsText().contains("status"))
    }

    /** 엔진 비활성 상태에서 /route 는 503(engine_unavailable) 을 반환해야 한다. */
    @Test
    fun routeReturns503WhenEngineDisabled() = testApplication {
        application {
            configureSerialization()
            configureStatusPages()
            configureRouting()
        }
        val resp = client.post("/route") {
            contentType(ContentType.Application.Json)
            setBody("""{"fromLat":36.35,"fromLon":127.35,"toLat":36.37,"toLon":127.38}""")
        }
        assertEquals(HttpStatusCode.ServiceUnavailable, resp.status)
    }
}
