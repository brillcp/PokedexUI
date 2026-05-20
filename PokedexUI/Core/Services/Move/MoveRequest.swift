import Networking

/// Requestable endpoints for move data.
enum MoveRequest: Requestable {
    case detail(String)
    case list(limit: Int)

    var encoding: Request.Encoding { .query }
    var httpMethod: HTTP.Method { .get }

    var endpoint: EndpointType {
        switch self {
            case .detail(let id): Endpoint.moveDetail(id)
            case .list:           Endpoint.moveList
        }
    }

    var parameters: HTTP.Parameters {
        switch self {
            case .detail: HTTP.Parameters()
            case .list(let limit):
                [ParameterKey.limit.rawValue: "\(limit)"]
        }
    }
}
