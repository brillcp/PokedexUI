import Networking

/// PokeAPI requests this service exposes.
enum PokemonRequest: Requestable {
    /// Paginated `/pokemon?limit&offset` summary list — returns name + url for
    /// each pokemon. The grid reads only this; full details are pulled lazily.
    case pokemonPage(offset: Int, limit: Int)
    /// Full `/pokemon/{id}` payload, used to hydrate one pokemon on tap.
    case details(String)
    /// `/pokemon-species/{id}` — habitat, flavor text, evolution chain ref,
    /// genus, gender rate, etc. Merged into `Pokemon` on hydration.
    case species(String)

    var encoding: Request.Encoding { .query }
    var httpMethod: HTTP.Method { .get }

    var endpoint: EndpointType {
        switch self {
            case .details(let id):    Endpoint.pokemonDetails(id)
            case .species(let id):    Endpoint.pokemonSpecies(id)
            case .pokemonPage:        Endpoint.pokemon
        }
    }

    var parameters: HTTP.Parameters {
        switch self {
            case .pokemonPage(let offset, let limit):
                return [
                    ParameterKey.offset.rawValue: "\(offset)",
                    ParameterKey.limit.rawValue: "\(limit)"
                ]
            default:
                return HTTP.Parameters()
        }
    }
}
