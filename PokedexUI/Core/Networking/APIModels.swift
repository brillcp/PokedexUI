import SwiftData

/// Generic `{ name, url }` row returned by every paginated PokeAPI list
/// endpoint. Persisted as a `@Model` so list responses can be cached even
/// before the per-item detail is fetched.
@Model
final class APIItem: Decodable {
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

/// Paginated PokeAPI list envelope. Used by every endpoint that returns
/// `{ count, results }`.
struct APIResponse: Decodable {
    /// Total number of items the endpoint can return. Used by paginated
    /// flows to know when to stop requesting more pages.
    let count: Int?
    let results: [APIItem]
}
