import Networking

/// An enum for requesting items
enum ItemRequest: Requestable {
    case items(limit: Int)

    var endpoint: EndpointType { Endpoint.items }
    var encoding: Request.Encoding { .query }
    var httpMethod: HTTP.Method { .get }

    var parameters: HTTP.Parameters {
        switch self {
        case .items(let limit):
            return ["limit": limit]
        }
    }
}
