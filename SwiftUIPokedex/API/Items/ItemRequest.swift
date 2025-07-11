import Networking

/// An enum for requesting items
enum ItemRequest: Requestable {
    case items(limit: Int)
    case next(offset: String, limit: String)

    var endpoint: EndpointType { Endpoint.items }
    var encoding: Request.Encoding { .query }
    var httpMethod: HTTP.Method { .get }

    var parameters: HTTP.Parameters {
        switch self {
            case .items(let limit):
                ["limit": limit]
            case .next(let offset, let limit):
                ["offset": offset, "limit": limit]
        }
    }

    enum ParameterKey: String {
        case offset
        case limit
    }
}
