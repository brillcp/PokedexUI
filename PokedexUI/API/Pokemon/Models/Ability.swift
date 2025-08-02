import SwiftData

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
