import SwiftData

@Model
final class Pokemon: Decodable {
    @Attribute(.unique) var id: Int
    var name: String
    var weight: Int
    var height: Int
    var isBookmarked: Bool = false
    var cries: Cries
    var sprite: Sprite
    var abilities: [Ability]
    var moves: [Move]
    var types: [Type]
    var stats: [Stat]

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
        moves = try container.decode(limitedTo: 10, forKey: .moves)
        types = try container.decode([Type].self, forKey: .types)
        stats = try container.decode([Stat].self, forKey: .stats)
    }
}

// MARK: - Private decoding helper fucntion
private extension KeyedDecodingContainer {
    func decode<T: Decodable>(limitedTo count: Int, forKey key: K, ) throws -> [T] {
        let container = try nestedUnkeyedContainer(forKey: key)
        var output = [T]()

        var tempContainer = container
        while !tempContainer.isAtEnd && output.count <= count {
            output.append(try tempContainer.decode(T.self))
        }
        return output
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

// MARK: - SwiftData models
@Model
final class Ability: Decodable {
    var ability: APIItem

    @Relationship(inverse: \Pokemon.abilities)
    var pokemon: Pokemon?

    private enum CodingKeys: String, CodingKey {
        case ability
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ability = try container.decode(APIItem.self, forKey: .ability)
    }

    init(ability: APIItem) {
        self.ability = ability
    }
}

@Model
final class Sprite: Decodable {
    var front: String
    var back: String?

    private enum CodingKeys: String, CodingKey {
        case front = "front_default"
        case back = "back_default"
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        front = try container.decode(String.self, forKey: .front)
        back = try container.decodeIfPresent(String.self, forKey: .back)
    }

    init(front: String, back: String?) {
        self.front = front
        self.back = back
    }
}

@Model
final class Move: Decodable {
    var move: APIItem

    @Relationship(inverse: \Pokemon.moves)
    var pokemon: Pokemon?

    private enum CodingKeys: String, CodingKey {
        case move
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        move = try container.decode(APIItem.self, forKey: .move)
    }

    init(move: APIItem) {
        self.move = move
    }
}

@Model
final class Cries: Decodable {
    var latest: String?

    private enum CodingKeys: String, CodingKey {
        case latest
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        latest = try container.decodeIfPresent(String.self, forKey: .latest)
    }

    init(latest: String?) {
        self.latest = latest
    }
}

@Model
final class Type: Decodable {
    var type: APIItem

    @Relationship(inverse: \Pokemon.types)
    var pokemon: Pokemon?

    private enum CodingKeys: String, CodingKey {
        case type
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(APIItem.self, forKey: .type)
    }

    init(type: APIItem) {
        self.type = type
    }
}

@Model
final class Stat: Decodable {
    var baseStat: Int
    var stat: APIItem

    @Relationship(inverse: \Pokemon.stats)
    var pokemon: Pokemon?

    private enum CodingKeys: String, CodingKey {
        case stat
        case baseStat = "base_stat"
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baseStat = try container.decode(Int.self, forKey: .baseStat)
        stat = try container.decode(APIItem.self, forKey: .stat)
    }

    init(baseStat: Int, stat: APIItem) {
        self.baseStat = baseStat
        self.stat = stat
    }
}

