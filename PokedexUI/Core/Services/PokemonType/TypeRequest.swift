import Networking

/// Requestable enum for `TypeService`.
enum TypeRequest: Requestable {
    case list
    case detail(String)

    var encoding: Request.Encoding { .query }
    var httpMethod: HTTP.Method { .get }

    var endpoint: EndpointType {
        switch self {
            case .list: Endpoint.typeList
            case .detail(let id): Endpoint.typeDetail(id)
        }
    }

    var parameters: HTTP.Parameters {
        switch self {
            case .list: [ParameterKey.limit.rawValue: "20"]
            case .detail: HTTP.Parameters()
        }
    }
}
