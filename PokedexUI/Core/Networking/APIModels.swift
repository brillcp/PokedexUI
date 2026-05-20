import SwiftData

/// Generic `{ name, url }` row returned by every paginated PokeAPI list endpoint.
@Model
final class APIItem: Decodable, Sendable {
    var name: String
    var url: String

    private enum CodingKeys: String, CodingKey {
        case name, url
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

/// Paginated PokeAPI list envelope containing `{ count, results }`.
struct APIResponse: Decodable, Sendable {
    let count: Int?
    let results: [APIItem]
}
