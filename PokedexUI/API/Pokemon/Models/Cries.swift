import SwiftData

@Model
final class Cries: Decodable {
    @Attribute var latest: String?

    private enum CodingKeys: String, CodingKey {
        case latest
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        latest = try container.decodeIfPresent(String.self, forKey: .latest)
    }

    init(latest: String?) {
        self.latest = latest
    }
}
