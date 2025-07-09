//
//  Model.swift
//  SwiftUIPokedex
//
//  Created by Viktor Gidlöf on 2021-11-12.
//

import Foundation

struct APIResponse: Decodable {
    let next: String
    let results: [APIItem]
}

struct APIItem: Decodable, Hashable {
    let name: String
    let url: String
}

struct PokemonDetails: Decodable, Equatable {
    static func == (lhs: PokemonDetails, rhs: PokemonDetails) -> Bool {
        lhs.id == rhs.id
    }
    
    let id: Int
    let name: String
    let weight: Int
    let height: Int
    let baseExperience: Int
    let forms: [APIItem]
    let sprite: Sprite
    let abilities: [Ability]
    let moves: [Move]
    let types: [Type]
    let stats: [Stat]
    
    private enum CodingKeys: String, CodingKey {
        case id, name, weight, height, forms, abilities, moves, types, stats
        case baseExperience = "base_experience"
        case sprite = "sprites"
    }
}

struct Sprite: Decodable {
    let url: String
    
    private enum CodingKeys: String, CodingKey {
        case url = "front_default"
    }
}

struct Ability: Decodable {
    let ability: APIItem
}

struct Move: Decodable {
    let move: APIItem
}

struct Type: Decodable {
    let type: APIItem
}

struct Stat: Decodable {
    let baseStat: Int
    let stat: APIItem
    
    private enum CodingKeys: String, CodingKey {
        case stat
        case baseStat = "base_stat"
    }
}

// MARK: - Mock pokemon
extension PokemonDetails {
    static var pikachu: PokemonDetails {
        PokemonDetails(
            id: 0,
            name: "Pika",
            weight: 0,
            height: 0,
            baseExperience: 0,
            forms: [],
            sprite: Sprite(url: "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/6.png"),
            abilities: [],
            moves: [],
            types: [.init(type: .init(name: "gunther", url: ""))],
            stats: []
        )
    }
}
