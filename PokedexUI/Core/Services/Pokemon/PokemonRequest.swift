import Networking

/// PokeAPI requests this service exposes.
enum PokemonRequest: Requestable {
    /// Single-shot `/pokemon?limit=1150` to fetch the entire national dex
    /// in one call. Used by the initial load path.
    case allPokemon
    /// Full `/pokemon/{id}` payload, used to hydrate one pokemon on tap.
    case details(String)
    /// `/pokemon-species/{id}`: habitat, flavor text, evolution chain ref,
    /// genus, gender rate, etc. Merged into `Pokemon` on hydration.
    case species(String)

    var encoding: Request.Encoding { .query }
    var httpMethod: HTTP.Method { .get }

    var endpoint: EndpointType {
        switch self {
            case .details(let id): Endpoint.pokemonDetails(id)
            case .species(let id): Endpoint.pokemonSpecies(id)
            case .allPokemon:      Endpoint.pokemon
        }
    }

    var parameters: HTTP.Parameters {
        switch self {
            case .allPokemon: [ParameterKey.limit.rawValue: "1150"]
            default: HTTP.Parameters()
        }
    }
}
