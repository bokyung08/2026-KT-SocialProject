package kt.dinjae.traffic.plugins

import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.plugins.statuspages.*
import io.ktor.server.response.*
import kt.dinjae.traffic.api.ErrorResponse
import kt.dinjae.traffic.routing.RoutingException

fun Application.configureStatusPages() {
    install(StatusPages) {
        exception<RoutingException> { call, cause ->
            call.respond(HttpStatusCode.UnprocessableEntity, ErrorResponse("routing_failed", cause.message))
        }
        exception<IllegalArgumentException> { call, cause ->
            call.respond(HttpStatusCode.BadRequest, ErrorResponse("invalid_argument", cause.message))
        }
        exception<Throwable> { call, cause ->
            call.respond(HttpStatusCode.InternalServerError, ErrorResponse("internal_error", cause.message))
        }
    }
}
