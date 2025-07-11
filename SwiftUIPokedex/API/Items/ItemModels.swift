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
extension ItemDetails: Hashable {

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: -
extension ItemDetails: Equatable {

    static func == (lhs: ItemDetails, rhs: ItemDetails) -> Bool {
        lhs.id == rhs.id
    }
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
