import SwiftData

/// Full hydrated pokemon record cached on first fetch.
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
    var moveNames: [String]
    var types: [Type]
    var stats: [Stat]
    var habitat: String?
    var flavorText: String?
    var genus: String? = nil
    var generationName: String? = nil
    var genderRate: Int = -1
    var captureRate: Int = 0
    var baseHappiness: Int = 0
    var evolutionChainId: String? = nil
    var isLegendary: Bool = false
    var isMythical: Bool = false

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
        moveNames: [String],
        types: [Type],
        stats: [Stat],
        habitat: String? = nil,
        flavorText: String? = nil,
        genus: String? = nil,
        generationName: String? = nil,
        genderRate: Int = -1,
        captureRate: Int = 0,
        baseHappiness: Int = 0,
        evolutionChainId: String? = nil,
        isLegendary: Bool = false,
        isMythical: Bool = false
    ) {
        self.id = id
        self.name = name
        self.weight = weight
        self.height = height
        self.cries = cries
        self.sprite = sprite
        self.abilities = abilities
        self.moveNames = moveNames
        self.types = types
        self.stats = stats
        self.habitat = habitat
        self.flavorText = flavorText
        self.genus = genus
        self.generationName = generationName
        self.genderRate = genderRate
        self.captureRate = captureRate
        self.baseHappiness = baseHappiness
        self.evolutionChainId = evolutionChainId
        self.isLegendary = isLegendary
        self.isMythical = isMythical
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name).capitalized
        weight = try container.decode(Int.self, forKey: .weight)
        height = try container.decode(Int.self, forKey: .height)
        cries = try container.decode(Cries.self, forKey: .cries)
        sprite = try container.decode(Sprite.self, forKey: .sprite)
        abilities = try container.decode([Ability].self, forKey: .abilities)
        moveNames = try container.decode([MoveRef].self, forKey: .moves).map(\.move.name)
        types = try container.decode([Type].self, forKey: .types)
        stats = try container.decode([Stat].self, forKey: .stats)
    }
}

extension Pokemon {
    var frontSprite: String { sprite.front }
    var backSprite: String? { sprite.back }
}

extension Pokemon {
    static var pikachu: Pokemon {
        Pokemon(
            id: 25,
            name: "Pikachu",
            weight: 60,
            height: 4,
            cries: Cries(latest: nil),
            sprite: Sprite(
                front: "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/3.png",
                back: "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/back/6.png"
            ),
            abilities: [
                Ability(ability: APIItem(name: "static", url: "")),
                Ability(ability: APIItem(name: "lightning-rod", url: ""))
            ],
            moveNames: ["mega-punch", "pay-day", "thunder-punch", "slam", "thunderbolt"],
            types: [
                Type(type: APIItem(name: "electric", url: ""))
            ],
            stats: [
                Stat(baseStat: 35, stat: APIItem(name: "hp", url: "")),
                Stat(baseStat: 55, stat: APIItem(name: "attack", url: "")),
                Stat(baseStat: 40, stat: APIItem(name: "defense", url: "")),
                Stat(baseStat: 50, stat: APIItem(name: "special-attack", url: "")),
                Stat(baseStat: 50, stat: APIItem(name: "special-defense", url: "")),
                Stat(baseStat: 90, stat: APIItem(name: "speed", url: ""))
            ],
            habitat: "Forest",
            flavorText: "This Pokemon is electric. This Pokemon is electric. This Pokemon is electric. This Pokemon is electric. ",
            genderRate: 5,
            evolutionChainId: "10"
        )
    }
}

// MARK: - SwiftData models

/// Ability slot on a `Pokemon`. Wraps an `APIItem` reference (name + URL)
/// to the canonical ability record on PokeAPI.
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

/// Default front + optional back sprite URLs.
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

/// Throwaway DTO for decoding PokeAPI's `"moves": [{"move": {...}}]` array.
private struct MoveRef: Decodable {
    let move: APIItem
}

/// Audio cry URLs. PokeAPI exposes both a legacy and a latest variant;
/// PokedexUI plays `latest` if present.
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

/// One of a pokemon's 1 or 2 elemental types. Wraps an `APIItem` so the type
/// name aligns with the `TypeChart` keys used by the damage formula.
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

/// One of the six base stats (HP, attack, defense, sp.atk, sp.def, speed)
/// with its raw integer value. Used by the battle engine + stats UI on the
/// detail view.
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

