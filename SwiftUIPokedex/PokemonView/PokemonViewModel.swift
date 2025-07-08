//
//  PokemonViewModel.swift
//  SwiftUIPokedex
//
//  Created by Viktor Gidlöf on 2025-07-08.
//

import SwiftUI

protocol PokemonViewModelProtocol: ObservableObject {
    var image: UIImage? { get }
    var color: Color? { get }
    var isLight: Bool { get }
    var url: String { get }
    var id: Int { get }
}

// MARK: -
final class PokemonViewModel {
    private let pokemon: PokemonDetails

    @Published var image: UIImage?
    @Published var color: Color?

    init(pokemon: PokemonDetails) {
        self.pokemon = pokemon
    }
}

// MARK: - PokemonViewModelProtocol
extension PokemonViewModel: PokemonViewModelProtocol {
    var id: Int {
        pokemon.id
    }

    var isLight: Bool {
        color?.isLight ?? false
    }

    var url: String {
        pokemon.sprite.url
    }
}

// MARK: - Equatable
extension PokemonViewModel: Equatable {
    static func == (lhs: PokemonViewModel, rhs: PokemonViewModel) -> Bool {
        lhs.id == rhs.id
    }
}
