//
//  PokemonService.swift
//  SwiftUIPokedex
//
//  Created by Viktor Gidlöf on 2021-11-12.
//

import Foundation
import Combine

final class PokemonService: API, ObservableObject {
    
    // MARK: Private properties
    private var response: APIResponse?

    // MARK: - Public properties
    @Published var pokemon = [PokemonViewModel]()

    // MARK: - Public functions
    func requestPokemon() async throws -> [PokemonViewModel] {
        let newResponse = try await requestPokemon(at: response?.next)
        response = newResponse

        let details = try await withThrowingTaskGroup(of: PokemonDetails.self) { group in
            for result in newResponse.results {
                guard let url = URL(string: result.url) else { continue }
                group.addTask {
                    try await self.pokemonDetails(from: url)
                }
            }

            var collected = [PokemonDetails]()
            for try await pokemon in group {
                collected.append(pokemon)
            }
            return collected
        }

        return details.sorted(by: { $0.id < $1.id }).map { PokemonViewModel(pokemon: $0) }
    }
}

// MARK: - Private functions
private extension PokemonService {
    func pokemonDetails(from url: URL) async throws -> PokemonDetails {
        let request = URLRequest(url: url)
        let result: PokemonDetails = try await NetworkAgent.execute(request)
        return result
    }

    func requestPokemon(at urlString: String?) async throws -> APIResponse {
        let finalURL: URL = {
            if let urlString, let url = URL(string: urlString) {
                return url
            } else {
                return baseURL.appendingPathComponent(PokemonService.ItemType.pokemon.rawValue)
            }
        }()

        let request = URLRequest(url: finalURL)
        return try await NetworkAgent.execute(request)
    }
}
