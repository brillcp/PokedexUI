import SwiftData

@Model
final class APIItem: Decodable {
    @Attribute var name: String
    @Attribute var url: String

    private enum CodingKeys: String, CodingKey {
        case name
        case url
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.url = try container.decode(String.self, forKey: .url)
    }

    init(name: String, url: String) {
        self.name = name
        self.url = url
    }
}

struct APIResponse: Decodable {
    let results: [APIItem]
}
