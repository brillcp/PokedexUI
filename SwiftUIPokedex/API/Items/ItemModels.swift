import Foundation

struct ItemDetails: Decodable {
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
    var items: [ItemDetails] = []
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

extension String {
    var pretty: String {
        self
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }
}
