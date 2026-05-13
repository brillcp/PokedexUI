import Networking

/// A protocol defining the interface for fetching Pokémon data.
protocol PokemonServiceProtocol {
    /// The underlying API service used to fetch and decode Pokémon data.
    var service: APIService<PokemonService.Config> { get }

    /// Requests the initial set of Pokémon.
    ///
    /// - Returns: An array of `PokemonViewModel` objects.
    /// - Throws: An error if the request or decoding fails.
    func requestPokemon() async throws -> [PokemonViewModel]
}
// MARK: - PokemonService implementation
/// A concrete implementation of `PokemonServiceProtocol` for interacting with Pokémon-related endpoints of the PokeAPI.
final class PokemonService {
    /// The generic API service responsible for fetching and decoding Pokémon data.
    let service: APIService<Config>

    /// Creates a new `PokemonService` with an optional custom API service.
    ///
    /// - Parameter service: A configured API service. Defaults to one using `PokemonService.Config`.
    init(service: APIService<Config> = .init(config: Config())) {
        self.service = service
    }
}

// MARK: - PokemonServiceProtocol
extension PokemonService: PokemonServiceProtocol {
    /// Requests the initial set of Pokémon from the API.
    ///
    /// - Returns: An array of `PokemonViewModel` representing the fetched Pokémon.
    /// - Throws: An error if the network request or decoding fails.
    func requestPokemon() async throws -> [PokemonViewModel] {
        try await service.requestData()
    }
}

// MARK: - PokemonService configuration
extension PokemonService {
    /// A configuration used by `APIService` to define Pokémon-specific requests and response transformation.
    struct Config: ServiceConfiguration {
        typealias ResponseType = Pokemon & Sendable
        typealias OutputModel = PokemonViewModel

        /// Builds the request used to fetch the species list (one entry per Pokédex species).
        func createRequest() -> Requestable {
            PokemonRequest.speciesList
        }

        /// Builds a request for fetching species data, used as the entry point for each detail.
        func createDetailRequest(from urlComponent: String) -> Requestable {
            PokemonRequest.species(urlComponent)
        }

        /// Fetches species first, resolves the default variety's Pokémon URL, then fetches
        /// that Pokémon and attaches species-derived habitat and flavor text.
        func fetchDetail(from urlComponent: String, networkService: Network.Service) async throws -> ResponseType {
            let species: PokemonSpecies = try await networkService.request(
                PokemonRequest.species(urlComponent)
            )

            let pokemonId: String
            if let variety = species.defaultVariety,
               let url = try? variety.pokemon.url.asURL() {
                pokemonId = url.lastPathComponent
            } else {
                pokemonId = urlComponent
            }

            let pokemon: Pokemon = try await networkService.request(
                PokemonRequest.details(pokemonId)
            )
            pokemon.habitat = species.habitat?.name
            pokemon.flavorText = species.englishFlavorText
            pokemon.genus = species.englishGenus
            pokemon.generationName = species.generation?.name
            pokemon.genderRate = species.genderRate
            pokemon.captureRate = species.captureRate
            pokemon.baseHappiness = species.baseHappiness ?? 0
            pokemon.hatchCounter = species.hatchCounter ?? 0
            pokemon.eggGroups = species.eggGroups.map(\.name)
            pokemon.evolutionChainId = species.evolutionChain?.id
            pokemon.isLegendary = species.isLegendary
            pokemon.isMythical = species.isMythical
            return pokemon
        }

        /// Transforms an array of detailed Pokémon data into sorted `PokemonViewModel` instances.
        ///
        /// - Parameter response: The array of detailed Pokémon data.
        /// - Returns: A sorted array of `PokemonViewModel` by Pokémon ID.
        func transformResponse(_ response: [ResponseType]) -> [OutputModel] {
            response
                .sorted(by: { $0.id < $1.id })
                .map { PokemonViewModel(pokemon: $0) }
        }
    }
}
