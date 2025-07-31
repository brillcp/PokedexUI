import SwiftData

@Model
final class ItemDetail: Decodable {
    @Attribute(.unique) var id: Int
    @Attribute var name: String
    @Relationship var sprites: ItemSprite
    @Relationship var category: APIItem
    @Relationship var effect: [Effect]

    private enum CodingKeys: String, CodingKey {
        case id, name, sprites, category
        case effect = "effect_entries"
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.sprites = try container.decode(ItemSprite.self, forKey: .sprites)
        self.category = try container.decode(APIItem.self, forKey: .category)
        self.effect = try container.decode([Effect].self, forKey: .effect)
    }

    init(id: Int, name: String, sprites: ItemSprite, category: APIItem, effect: [Effect]) {
        self.id = id
        self.name = name
        self.sprites = sprites
        self.category = category
        self.effect = effect
    }
}

// MARK: -
@Model
final class ItemData {
    @Attribute var title: String
    @Attribute var items: [ItemDetail]

    init(title: String, items: [ItemDetail]) {
        self.title = title
        self.items = items
    }
}

extension ItemData {
    var icon: String? {
        items.first?.sprites.default
    }
}

// MARK: -
@Model
final class ItemSprite: Decodable {
    @Attribute var `default`: String

    private enum CodingKeys: String, CodingKey {
        case `default` = "default"
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.default = try container.decode(String.self, forKey: .default)
    }

    init(default: String) {
        self.default = `default`
    }
}

// MARK: -
@Model
final class Effect: Decodable {
    @Attribute var effect: String

    private enum CodingKeys: String, CodingKey {
        case effect
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.effect = try container.decode(String.self, forKey: .effect)
    }

    init(effect: String) {
        self.effect = effect
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
