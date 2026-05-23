import Networking

/// All PokeAPI endpoint paths.
enum Endpoint {
    case itemDetails(String)
    case pokemonDetails(String)
    case pokemonSpecies(String)
    case pokemon
    case items
    case evolutionChain(String)
}

extension Endpoint: EndpointType {
    var path: String {
        switch self {
            case .itemDetails(let id): return "item/\(id)"
            case .pokemonDetails(let id): return "pokemon/\(id)"
            case .pokemonSpecies(let id): return "pokemon-species/\(id)"
            case .pokemon: return "pokemon"
            case .items: return "item"
            case .evolutionChain(let id): return "evolution-chain/\(id)"
        }
    }
}
