import Networking

/// Requestable enum for `MoveService`. `detail(name)` resolves one move,
/// `list(limit:)` returns the bulk index used by `MovePrefetcher`.
enum MoveRequest: Requestable {
    case detail(String)
    /// Bulk list with explicit limit. Used by `MovePrefetcher` to discover every
    /// move name in one call so we can fetch and persist them upfront.
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
