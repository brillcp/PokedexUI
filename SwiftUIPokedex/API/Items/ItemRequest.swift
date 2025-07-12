import Networking

/// An enum for requesting items
enum ItemRequest: Requestable {
    case items(limit: Int)
    case next(offset: String, limit: String)
    case details(String)

    var encoding: Request.Encoding { .query }
    var httpMethod: HTTP.Method { .get }

    var endpoint: EndpointType {
        switch self {
            case .details(let id):
                Endpoint.itemDetails(id)
            default:
                Endpoint.items
        }
    }

    var parameters: HTTP.Parameters {
        switch self {
            case .items(let limit):
                ["limit": limit]
            case .next(let offset, let limit):
                ["offset": offset, "limit": limit]
            default:
                HTTP.Parameters()
        }
    }

    enum ParameterKey: String {
        case offset
        case limit
    }
}
