import Networking

/// Requestable endpoints for evolution chain data.
enum EvolutionRequest: Requestable {
    case chain(String)

    var encoding: Request.Encoding { .query }
    var httpMethod: HTTP.Method { .get }
    var parameters: HTTP.Parameters { HTTP.Parameters() }

    var endpoint: EndpointType {
        switch self {
            case .chain(let id): Endpoint.evolutionChain(id)
        }
    }
}
