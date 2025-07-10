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
    var types: String { get }
    var abilities: String { get }
    var name: String { get }
    var stats: [Stat] { get }
    var moves: String { get }
    var height: String { get }
    var weight: String { get }
    var url: String { get }
    var id: Int { get }

    func loadSprite() async
}

// MARK: -
final class PokemonViewModel {
    private let imageLoader: ImageLoader
    private let pokemon: PokemonDetails

    @Published var image: UIImage?
    @Published var color: Color?

    init(pokemon: PokemonDetails, imageLoader: ImageLoader = .shared) {
        self.imageLoader = imageLoader
        self.pokemon = pokemon
    }
}

// MARK: - PokemonViewModelProtocol
extension PokemonViewModel: PokemonViewModelProtocol {
    var id: Int {
        pokemon.id
    }

    var name: String {
        pokemon.name.capitalized
    }

    var height: String {
        "\(Double(pokemon.height) / 10.0) m"
    }

    var weight: String {
        "\(Double(pokemon.weight) / 10.0) kg"
    }

    var isLight: Bool {
        color?.isLight ?? false
    }

    var url: String {
        pokemon.sprite.url
    }

    var types: String {
        pokemon.types
            .map { $0.type.name.capitalized }
            .joined(separator: ", ")
    }

    var abilities: String {
        pokemon.abilities
            .map { $0.ability.name.capitalized }
            .joined(separator: ", ")

    }

    var stats: [Stat] {
        pokemon.stats
    }

    var moves: String {
        pokemon.moves[0 ... 20]
            .map { $0.move.name.capitalized }
            .joined(separator: ", ")
    }

    @MainActor
    func loadSprite() async {
        image = await imageLoader.loadImage(from: url)
        color = Color(uiColor: image?.dominantColor ?? .darkGray)
    }
}

// MARK: - Equatable
extension PokemonViewModel: Equatable {
    static func == (lhs: PokemonViewModel, rhs: PokemonViewModel) -> Bool {
        lhs.id == rhs.id
    }
}
