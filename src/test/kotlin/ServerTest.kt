package kt.dinjae.pm_safeline

import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import io.ktor.server.testing.*
import kt.dinjae.pm_safeline.plugins.configureCors
import kt.dinjae.pm_safeline.plugins.configureSerialization
import kt.dinjae.pm_safeline.plugins.configureStatusPages
import kt.dinjae.pm_safeline.tashu.TashuStationResponseMapper
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.*

class ServerTest {

    @Test
    fun officialTashuResponseMapsToFlutterStationDto() {
        val batch =
            TashuStationResponseMapper().map(
                """
                {
                  "count": 1,
                  "next": null,
                  "previous": null,
                  "results": [
                    {
                      "id": "ST0003",
                      "name": "탄방동 한사랑병원",
                      "name_en": "Han Sarang Hospital",
                      "name_cn": "",
                      "x_pos": 36.348446,
                      "y_pos": 127.390052,
                      "address": "대전광역시 서구 탄방동 730",
                      "parking_count": 1
                    }
                  ]
                }
                """.trimIndent(),
            )

        assertEquals(1, batch.totalCount)
        val station = batch.stations.single()
        assertEquals("ST0003", station.id)
        assertEquals("탄방동 한사랑병원", station.name)
        assertEquals(36.348446, station.lat)
        assertEquals(127.390052, station.lon)
        assertEquals(1, station.availableBikes)
        assertNull(station.totalDocks)
        assertNull(station.returnableDocks)
        assertNull(station.updatedAt)
    }

    @Test
    fun officialTashuResponseAcceptsNumericStringsAndPreservesTotalCount() {
        val batch =
            TashuStationResponseMapper().map(
                """
                {
                  "count": "1374",
                  "results": [
                    {
                      "id": "ST0003",
                      "name": "탄방동 한사랑병원",
                      "x_pos": "36.348446",
                      "y_pos": "127.390052",
                      "address": "대전광역시 서구 탄방동 730",
                      "parking_count": "2"
                    }
                  ]
                }
                """.trimIndent(),
            )

        assertEquals(1374, batch.totalCount)
        assertEquals(36.348446, batch.stations.single().lat)
        assertEquals(127.390052, batch.stations.single().lon)
        assertEquals(2, batch.stations.single().availableBikes)
    }
    @Test
    fun invalidOfficialTashuResponseFailsInsteadOfReturningFallback() {
        assertFails {
            TashuStationResponseMapper().map(
                """{"results":[{"id":"ST0003","name":"대여소"}]}""",
            )
        }
    }

    /** 라우팅 엔진 없이도(osmFile 미설정) 서버가 기동되고 /health 가 응답하는지. */
    @Test
    fun healthEndpointRespondsOk() = testApplication {
        application {
            configureCors()
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
            configureCors()
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

    @Test
    fun tashuStationsReturnsErrorWithoutEnvironmentConfiguration() = testApplication {
        application {
            configureCors()
            configureSerialization()
            configureStatusPages()
            configureRouting()
        }

        val resp = client.get("/tashu/stations")

        assertEquals(HttpStatusCode.ServiceUnavailable, resp.status)
        val payload = Json.parseToJsonElement(resp.bodyAsText()).jsonObject
        assertEquals("error", payload.getValue("source").jsonPrimitive.content)
        assertEquals("0", payload.getValue("count").jsonPrimitive.content)
        assertTrue(payload.getValue("stations").jsonArray.isEmpty())
        assertTrue(
            payload.getValue("message").jsonPrimitive.content.contains("설정되지 않았습니다"),
        )
    }

    @Test
    fun tashuStationsPreflightAllowsFlutterWebLocalhost() = testApplication {
        application {
            configureCors()
            configureSerialization()
            configureStatusPages()
            configureRouting()
        }
        val origin = "http://127.0.0.1:53147"
        val resp = client.options("/tashu/stations") {
            header(HttpHeaders.Origin, origin)
            header(HttpHeaders.AccessControlRequestMethod, HttpMethod.Get.value)
            header(HttpHeaders.AccessControlRequestHeaders, "accept")
        }
        assertEquals(HttpStatusCode.OK, resp.status)
        assertEquals(origin, resp.headers[HttpHeaders.AccessControlAllowOrigin])
    }

    /** Flutter Web 개발 origin의 OPTIONS /route 사전 요청을 CORS 플러그인이 처리한다. */
    @Test
    fun routePreflightAllowsFlutterWebLocalhost() = testApplication {
        application {
            configureCors()
            configureSerialization()
            configureStatusPages()
            configureRouting()
        }
        val origin = "http://localhost:53147"
        val resp = client.options("/route") {
            header(HttpHeaders.Origin, origin)
            header(HttpHeaders.AccessControlRequestMethod, HttpMethod.Post.value)
            header(HttpHeaders.AccessControlRequestHeaders, "content-type,accept")
        }
        assertEquals(HttpStatusCode.OK, resp.status)
        assertEquals(origin, resp.headers[HttpHeaders.AccessControlAllowOrigin])
        assertTrue(
            resp.headers.getAll(HttpHeaders.AccessControlAllowHeaders).orEmpty().any { it.contains(HttpHeaders.ContentType) },
            "Content-Type가 허용되어야 합니다. headers=${resp.headers.entries()}",
        )
        assertNull(resp.headers[HttpHeaders.AccessControlAllowCredentials])
    }
}