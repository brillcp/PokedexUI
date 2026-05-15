import Networking

/// Requestable enum for `EvolutionService`. `chain(id)` resolves one full
/// evolution tree from the trailing path component of its URL.
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
