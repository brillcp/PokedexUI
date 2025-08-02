import SwiftData

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
