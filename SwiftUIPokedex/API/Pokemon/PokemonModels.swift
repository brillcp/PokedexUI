import Foundation

struct PokemonDetails: Decodable {
    let id: Int
    let name: String
    let weight: Int
    let height: Int
    let baseExperience: Int
    let sprite: Sprite
    let abilities: [Ability]
    let moves: [Move]
    let types: [Type]
    let stats: [Stat]

    private enum CodingKeys: String, CodingKey {
        case id, name, weight, height, abilities, moves, types, stats
        case baseExperience = "base_experience"
        case sprite = "sprites"
    }
}

// MARK: -
struct Sprite: Decodable {
    let url: String

    private enum CodingKeys: String, CodingKey {
        case url = "front_default"
    }
}

// MARK: -
struct Ability: Decodable {
    let ability: APIItem
}

// MARK: -
struct Move: Decodable {
    let move: APIItem
}

// MARK: -
struct Type: Decodable {
    let type: APIItem
}

// MARK: -
struct Stat: Decodable, Identifiable {
    var id = UUID()
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
            sprite: Sprite(url: "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/6.png"),
            abilities: [.init(ability: .init(name: "Hp", url: ""))],
            moves: [.init(move: .init(name: "Move", url: ""))],
            types: [.init(type: .init(name: "gunther", url: ""))],
            stats: [.init(baseStat: 69, stat: .init(name: "stat", url: ""))]
        )
    }
}
