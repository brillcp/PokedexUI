import Foundation

struct Pokemon: Decodable {
    let id: Int
    let name: String
    let weight: Int
    let height: Int
    let baseExperience: Int
    let cries: Cries
    let sprite: Sprite
    let abilities: [Ability]
    let moves: [Move]
    let types: [Type]
    let stats: [Stat]

    private enum CodingKeys: String, CodingKey {
        case id, name, weight, height, abilities, moves, types, stats, cries
        case baseExperience = "base_experience"
        case sprite = "sprites"
    }
}

// MARK: -
struct Cries: Decodable {
    let latest: String?
}

// MARK: -
struct Sprite: Decodable {
    let front: String
    let back: String

    private enum CodingKeys: String, CodingKey {
        case front = "front_default"
        case back = "back_default"
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

// MARK: - Formatted properties
extension Pokemon {
    var capitalizedName: String {
        name.capitalized
    }

    var formattedHeight: String {
        "\(Double(height) / 10.0) m"
    }

    var formattedWeight: String {
        "\(Double(weight) / 10.0) kg"
    }

    var typeList: String {
        types.map { $0.type.name.capitalized }.joined(separator: ", ")
    }

    var abilityList: String {
        abilities.map { $0.ability.name.capitalized }.joined(separator: ",\n\n")
    }

    var moveList: String {
        let end = min(moves.count, 20)
        return moves.prefix(end).map { $0.move.name.capitalized }.joined(separator: ", ")
    }
}

// MARK: - Mock pokemon
extension Pokemon {
    static var pikachu: Pokemon {
        Pokemon(
            id: 0,
            name: "Pika",
            weight: 0,
            height: 0,
            baseExperience: 0,
            cries: .init(latest: nil),
            sprite: Sprite(
                front: "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/25.png",
                back: "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/back/25.png"),
            abilities: [.init(ability: .init(name: "Hp", url: ""))],
            moves: [.init(move: .init(name: "Move", url: ""))],
            types: [.init(type: .init(name: "gunther", url: ""))],
            stats: [.init(baseStat: 69, stat: .init(name: "stat", url: ""))]
        )
    }
}
