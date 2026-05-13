import Networking

enum MoveRequest: Requestable {
    case detail(String)

    var encoding: Request.Encoding { .query }
    var httpMethod: HTTP.Method { .get }
    var parameters: HTTP.Parameters { HTTP.Parameters() }

    var endpoint: EndpointType {
        switch self {
            case .detail(let id): Endpoint.moveDetail(id)
        }
    }
}
