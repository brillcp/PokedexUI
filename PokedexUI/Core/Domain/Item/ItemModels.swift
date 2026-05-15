import SwiftData

/// One individual item from PokeAPI (Pokéball, Potion, TM, etc.). Stores
/// the localized display name + sprite + category reference + effect list.
@Model
final class ItemDetail: Decodable {
    @Attribute(.unique) var id: Int
    var name: String
    var prettyName: String = ""
    var sprites: ItemSprite?
    var category: APIItem
    @Relationship var effect: [Effect]

    private enum CodingKeys: String, CodingKey {
        case id, name, sprites, category
        case effect = "effect_entries"
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        let decodedName = try container.decode(String.self, forKey: .name)
        self.name = decodedName
        self.prettyName = decodedName.pretty
        self.sprites = try container.decodeIfPresent(ItemSprite.self, forKey: .sprites)
        self.category = try container.decode(APIItem.self, forKey: .category)
        self.effect = try container.decode([Effect].self, forKey: .effect)
    }

    init(id: Int, name: String, sprites: ItemSprite?, category: APIItem, effect: [Effect]) {
        self.id = id
        self.name = name
        self.prettyName = name.pretty
        self.sprites = sprites
        self.category = category
        self.effect = effect
    }
}

extension ItemDetail {
    /// First Effect's short text, pre-formatted. Empty string when no effect available.
    var prettyEffect: String {
        effect.first?.prettyEffect ?? ""
    }
}

// MARK: -

/// Item category bucket (e.g. "Standard balls", "Healing", "Berries"). Holds
/// the localized title + the list of `ItemDetail`s inside that category.
@Model
final class ItemData {
    var title: String
    var prettyTitle: String = ""
    var items: [ItemDetail]

    init(title: String, items: [ItemDetail]) {
        self.title = title
        self.prettyTitle = title.pretty
        self.items = items
    }
}

extension ItemData {
    var icon: String? {
        items.first?.sprites?.default
    }
}

// MARK: -

/// Optional default sprite URL for an item. Items without official sprites
/// (rare) decode to `nil`.
@Model
final class ItemSprite: Decodable {
    var `default`: String?

    private enum CodingKeys: String, CodingKey {
        case `default` = "default"
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.default = try container.decodeIfPresent(String.self, forKey: .default)
    }

    init(default: String?) {
        self.default = `default`
    }
}

// MARK: -

/// Short-form effect text for an item ("Restores 20 HP", etc.). PokeAPI
/// ships one effect per language; we keep the raw short text and a
/// pre-formatted `prettyEffect` for display.
@Model
final class Effect: Decodable {
    var effect: String
    var prettyEffect: String = ""

    @Relationship(inverse: \ItemDetail.effect)
    var itemDetail: ItemDetail?

    private enum CodingKeys: String, CodingKey {
        case effect = "short_effect"
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try container.decode(String.self, forKey: .effect)
        self.effect = decoded
        self.prettyEffect = decoded.pretty
    }

    init(effect: String) {
        self.effect = effect
        self.prettyEffect = effect.pretty
    }
}

// MARK: -  Mock item
extension ItemDetail {
    static var common: ItemDetail {
        .init(
            id: 0,
            name: "Item",
            sprites: .init(
                default: "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/items/honey.png"
            ),
            category: .init(name: "category", url: ""),
            effect: [
                .init(effect: "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat")
            ]
        )
    }
}
