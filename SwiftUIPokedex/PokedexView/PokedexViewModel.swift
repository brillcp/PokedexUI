//
//  PokedexViewModel.swift
//  SwiftUIPokedex
//
//  Created by Viktor Gidlöf on 2025-07-08.
//

import Foundation

protocol PokedexViewModelProtocol: ObservableObject {
    var pokemon: [PokemonViewModel] { get }
    var isLoading: Bool { get }

    func requestPokemon() async
}

// MARK: -
final class PokedexViewModel {
    private let pokemonService: PokemonAPI

    @Published var pokemon: [PokemonViewModel] = []
    @Published var isLoading: Bool = false

    init(pokemonService: PokemonAPI = PokemonAPI()) {
        self.pokemonService = pokemonService
    }
}

// MARK: - PokedexViewModelProtocol
extension PokedexViewModel: PokedexViewModelProtocol {
    @MainActor
    func requestPokemon() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            pokemon = try await pokemonService.requestPokemon()
        } catch {
            print(error.localizedDescription)
        }
    }
}
