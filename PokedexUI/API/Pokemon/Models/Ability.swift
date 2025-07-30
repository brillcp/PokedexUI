import SwiftData

@Model
final class Ability: Decodable {
    @Relationship var ability: APIItem

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
