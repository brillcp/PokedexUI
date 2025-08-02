import SwiftData

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
