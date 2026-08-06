package kt.dinjae.pm_safeline.tashu

import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.time.Duration
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kt.dinjae.pm_safeline.Dotenv
import kt.dinjae.pm_safeline.api.TashuStationDto
import org.slf4j.Logger

enum class TashuFailureKind { CONFIGURATION, UPSTREAM, PARSING }

class TashuStationException(
    val kind: TashuFailureKind,
    val clientMessage: String,
    val failureReason: String,
    cause: Throwable? = null,
) : RuntimeException(clientMessage, cause)

data class TashuStationBatch(
    val totalCount: Int,
    val stations: List<TashuStationDto>,
)

class TashuStationService private constructor(
    private val remoteProvider: TashuStationProvider?,
    private val logger: Logger,
) {
    suspend fun stations(): TashuStationBatch {
        val provider =
            remoteProvider
                ?: throwFailure(
                    TashuStationException(
                        kind = TashuFailureKind.CONFIGURATION,
                        clientMessage = "TASHU_API_KEY 또는 TASHU_API_URL이 설정되지 않았습니다.",
                        failureReason = "missing_environment_variables",
                    ),
                )

        return try {
            val batch = provider.fetchStations()
            logger.info("[Tashu Backend] source=api")
            logger.info("[Tashu Backend] totalCount={}", batch.totalCount)
            logger.info("[Tashu Backend] mappedCount={}", batch.stations.size)
            batch
        } catch (error: TashuStationException) {
            throwFailure(error)
        } catch (error: Throwable) {
            throwFailure(
                TashuStationException(
                    kind = TashuFailureKind.UPSTREAM,
                    clientMessage = "타슈 API 호출 실패",
                    failureReason = "unexpected_${error::class.simpleName ?: "error"}",
                    cause = error,
                ),
            )
        }
    }

    private fun throwFailure(error: TashuStationException): Nothing {
        logger.warn("[Tashu Backend] source=error")
        logger.warn("[Tashu Backend] failureReason={}", error.failureReason)
        throw error
    }

    companion object {
        fun fromEnvironment(logger: Logger): TashuStationService {
            val apiUrl = Dotenv.get("TASHU_API_URL")
            val apiKey = Dotenv.get("TASHU_API_KEY")
            val provider =
                if (apiUrl == null || apiKey == null) {
                    null
                } else {
                    HttpTashuStationProvider(apiUrl, apiKey)
                }
            return TashuStationService(provider, logger)
        }
    }
}

internal fun interface TashuStationProvider {
    suspend fun fetchStations(): TashuStationBatch
}

internal class HttpTashuStationProvider(
    private val apiUrl: String,
    private val apiKey: String,
    private val client: HttpClient =
        HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(5))
            .build(),
) : TashuStationProvider {
    private val json = Json { ignoreUnknownKeys = true }

    override suspend fun fetchStations(): TashuStationBatch = withContext(Dispatchers.IO) {
        val uri =
            try {
                resolveUri()
            } catch (error: Throwable) {
                throw TashuStationException(
                    kind = TashuFailureKind.CONFIGURATION,
                    clientMessage = "TASHU_API_URL 설정이 올바르지 않습니다.",
                    failureReason = "invalid_api_url",
                    cause = error,
                )
            }
        val request =
            HttpRequest.newBuilder(uri)
                .timeout(Duration.ofSeconds(10))
                .header("Accept", "application/json")
                .header("api-token", apiKey)
                .header("User-Agent", "PM-SafeLine-Tashu-Backend/1.0")
                .GET()
                .build()
        val response =
            try {
                client.send(request, HttpResponse.BodyHandlers.ofString())
            } catch (error: Throwable) {
                throw TashuStationException(
                    kind = TashuFailureKind.UPSTREAM,
                    clientMessage = "타슈 API 호출 실패",
                    failureReason = "request_failed_${error::class.simpleName ?: "error"}",
                    cause = error,
                )
            }
        if (response.statusCode() !in 200..299) {
            throw TashuStationException(
                kind = TashuFailureKind.UPSTREAM,
                clientMessage = "타슈 API 호출 실패",
                failureReason = "upstream_http_${response.statusCode()}",
            )
        }
        try {
            TashuStationResponseMapper(json).map(response.body())
        } catch (error: TashuStationException) {
            throw error
        } catch (error: Throwable) {
            throw TashuStationException(
                kind = TashuFailureKind.PARSING,
                clientMessage = "타슈 API 응답 파싱 실패",
                failureReason = "response_parsing_failed_${error::class.simpleName ?: "error"}",
                cause = error,
            )
        }
    }

    private fun resolveUri(): URI {
        val uri = URI.create(apiUrl)
        require(uri.scheme == "http" || uri.scheme == "https")
        return uri
    }
}

internal class TashuStationResponseMapper(
    private val json: Json = Json { ignoreUnknownKeys = true },
) {
    fun map(body: String): TashuStationBatch {
        val root = json.parseToJsonElement(body)
        if (root is JsonArray) {
            val stations = root.map { json.decodeFromJsonElement<TashuStationDto>(it) }
            return TashuStationBatch(totalCount = stations.size, stations = stations)
        }

        val response = root as? JsonObject
            ?: error("Tashu API response must be an object")
        val results = response["results"] as? JsonArray
            ?: error("Tashu API response must contain a results array")
        val totalCount = response.optionalInt("count") ?: results.size
        return TashuStationBatch(
            totalCount = totalCount,
            stations = results.map { mapOfficialStation(it.jsonObject) },
        )
    }

    private fun mapOfficialStation(station: JsonObject) =
        TashuStationDto(
            id = station.requiredText("id"),
            name = station.requiredText("name"),
            address = station.requiredText("address"),
            lat = station.requiredDouble("x_pos"),
            lon = station.requiredDouble("y_pos"),
            availableBikes = station.optionalInt("parking_count"),
            totalDocks = null,
            returnableDocks = null,
            updatedAt = null,
        )

    private fun JsonObject.requiredText(field: String): String {
        val value = primitive(field).content.trim()
        require(value.isNotEmpty()) { "Tashu field $field is empty" }
        return value
    }

    private fun JsonObject.requiredDouble(field: String): Double =
        primitive(field).content.toDoubleOrNull()
            ?: error("Tashu field $field is not a number")

    private fun JsonObject.optionalInt(field: String): Int? {
        val element = this[field] ?: return null
        if (element !is JsonPrimitive || element.content == "null") return null
        return element.content.toIntOrNull()
            ?: error("Tashu field $field is not an integer")
    }

    private fun JsonObject.primitive(field: String): JsonPrimitive =
        this[field] as? JsonPrimitive
            ?: error("Tashu field $field is missing")
}