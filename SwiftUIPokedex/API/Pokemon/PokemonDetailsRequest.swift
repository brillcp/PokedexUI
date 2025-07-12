import Networking

///// An enum for requesting pokemon detail data
//enum PokemonDetailsRequest: Requestable {
//    case details(String)
//
//    var encoding: Request.Encoding { .query }
//    var httpMethod: HTTP.Method { .get }
//
//    var endpoint: EndpointType {
//        switch self {
//        case .details(let id): return Endpoint.pokemonDetails(id)
//        }
//    }
//}
