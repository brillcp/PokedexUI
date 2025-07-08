//
//  PokemonAPI.swift
//  SwiftUIPokedex
//
//  Created by Viktor Gidlöf on 2021-11-12.
//

import Foundation
import Combine

final class PokemonAPI: API, ObservableObject {
    
    // MARK: Private properties
    private var response: APIResponse?

    // MARK: - Public properties
    @Published var pokemon = [PokemonDetails]()
    @Published var isLoading = false

    // MARK: - Public functions
    func requestPokemon() {
        guard !isLoading else { return }

        isLoading = true

        requestPokemon(at: response?.next)?.flatMap { response in
            Publishers.Sequence(sequence: response.results.compactMap { self.pokemonDetails(from: $0.url) })
                .flatMap { $0 }
                .collect()
        }
        .sink { result in
            switch result {
                case let .success(pokemon):
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.pokemon += pokemon.sorted(by: { $0.id < $1.id })
                    }
                case let .failure(error):
                    print(error.localizedDescription)
            }
        }
        .store(in: &cancellables)
    }
}

// MARK: - Private functions
private extension PokemonAPI {
    func pokemonDetails(from urlString: String) -> AnyPublisher<PokemonDetails, Error>? {
        guard let url = URL(string: urlString) else { return nil }
        return NetworkAgent.execute(URLRequest(url: url))
    }
    
    func requestPokemon(at urlString: String?) -> AnyPublisher<APIResponse, Error>? {
        let finalURL: URL
        
        if let urlString = urlString, let url = URL(string: urlString) {
            finalURL = url
        } else {
            finalURL = baseURL.appendingPathComponent(PokemonAPI.ItemType.pokemon.rawValue)
        }
        
        let request = URLRequest(url: finalURL)
        
        return NetworkAgent.execute(request)
            .handleEvents(receiveOutput: {
                self.response = $0
            })
            .eraseToAnyPublisher()
    }
}
