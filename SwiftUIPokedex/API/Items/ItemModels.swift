import Foundation

struct ItemDetail: Decodable {
    let id: Int
    let name: String
    let sprites: ItemSprite
    let category: APIItem
    let effect: [Effect]

    private enum CodingKeys: String, CodingKey {
        case id, name, sprites, category
        case effect = "effect_entries"
    }
}

// MARK: -
struct ItemData {
    var title: String? = nil
    var items: [ItemDetail] = []
}

// MARK: -
struct ItemSprite: Decodable {
    let `default`: String
}

// MARK: -
struct Effect: Decodable {
    let description: String

    private enum CodingKeys: String, CodingKey {
        case description = "effect"
    }
}

// MARK: - Query matching for search
extension ItemDetail {
    func matches(query: String) -> Bool {
        name.localizedCaseInsensitiveContains(query)
        || category.name.localizedCaseInsensitiveContains(query)
        || effect.first?.description.localizedCaseInsensitiveContains(query) == true
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
                .init(description: "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat")
            ]
        )
    }
}
