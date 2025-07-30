import SwiftData

@Model
final class Sprite: Decodable {
    @Attribute var front: String
    @Attribute var back: String?

    private enum CodingKeys: String, CodingKey {
        case front = "front_default"
        case back = "back_default"
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        front = try container.decode(String.self, forKey: .front)
        back = try container.decodeIfPresent(String.self, forKey: .back)
    }

    init(front: String, back: String) {
        self.front = front
        self.back = back
    }
}
