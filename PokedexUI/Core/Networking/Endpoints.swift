import Networking

/// An enumeration for all the possible endpoints for the backend
enum Endpoint {
    case itemDetails(String)
    case pokemonDetails(String)
    case pokemonSpecies(String)
    case pokemon
    case items
    case moveDetail(String)
    case moveList
    case typeDetail(String)
    case typeList
    case evolutionChain(String)
}

// MARK: - EndpointType
extension Endpoint: EndpointType {
    var path: String {
        switch self {
            case .itemDetails(let id): return "item/\(id)"
            case .pokemonDetails(let id): return "pokemon/\(id)"
            case .pokemonSpecies(let id): return "pokemon-species/\(id)"
            case .pokemon: return "pokemon"
            case .items: return "item"
            case .moveDetail(let id): return "move/\(id)"
            case .moveList: return "move"
            case .typeDetail(let id): return "type/\(id)"
            case .typeList: return "type"
            case .evolutionChain(let id): return "evolution-chain/\(id)"
        }
    }
}
