import Networking

/// An enumeration for all the possible endpoints for the backend
enum Endpoint {
    case itemDetails(String)
    case pokemonDetails(String)
    case pokemon
    case items
}

// MARK: - EndpointType
extension Endpoint: EndpointType {
    var path: String {
        switch self {
        case .itemDetails(let id): return "item/\(id)"
        case .pokemonDetails(let id): return "pokemon/\(id)"
        case .pokemon: return "pokemon"
        case .items: return "item"
        }
    }
}
