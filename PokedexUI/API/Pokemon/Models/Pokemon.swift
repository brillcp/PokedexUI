import SwiftData

@Model
final class Pokemon: Decodable {
    @Attribute(.unique) var id: Int
    @Attribute var name: String
    @Attribute var weight: Int
    @Attribute var height: Int
    @Relationship var cries: Cries
    @Relationship var sprite: Sprite
    @Relationship var abilities: [Ability]
    @Relationship var moves: [Move]
    @Relationship var types: [Type]
    @Relationship var stats: [Stat]

    private enum CodingKeys: String, CodingKey {
        case id, name, weight, height, cries, abilities, moves, types, stats
        case sprite = "sprites"
    }

    init(
        id: Int,
        name: String,
        weight: Int,
        height: Int,
        cries: Cries,
        sprite: Sprite,
        abilities: [Ability],
        moves: [Move],
        types: [Type],
        stats: [Stat]
    ) {
        self.id = id
        self.name = name
        self.weight = weight
        self.height = height
        self.cries = cries
        self.sprite = sprite
        self.abilities = abilities
        self.moves = moves
        self.types = types
        self.stats = stats
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        weight = try container.decode(Int.self, forKey: .weight)
        height = try container.decode(Int.self, forKey: .height)
        cries = try container.decode(Cries.self, forKey: .cries)
        sprite = try container.decode(Sprite.self, forKey: .sprite)
        abilities = try container.decode([Ability].self, forKey: .abilities)
        moves = try container.decode([Move].self, forKey: .moves)
        types = try container.decode([Type].self, forKey: .types)
        stats = try container.decode([Stat].self, forKey: .stats)
    }
}

// MARK: - Formatted properties (not persisted)
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
            cries: Cries(latest: nil),
            sprite: Sprite(
                front: "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/25.png",
                back: "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/back/25.png"
            ),
            abilities: [Ability(ability: APIItem(name: "Hp", url: ""))],
            moves: [Move(move: APIItem(name: "Move", url: ""))],
            types: [Type(type: APIItem(name: "gunther", url: ""))],
            stats: [Stat(baseStat: 69, stat: APIItem(name: "stat", url: ""))]
        )
    }
}

