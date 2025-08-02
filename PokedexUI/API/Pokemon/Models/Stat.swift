import SwiftData

@Model
final class Stat: Decodable {
    var baseStat: Int
    var stat: APIItem

    @Relationship(inverse: \Pokemon.stats)
    var pokemon: Pokemon?

    private enum CodingKeys: String, CodingKey {
        case stat
        case baseStat = "base_stat"
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baseStat = try container.decode(Int.self, forKey: .baseStat)
        stat = try container.decode(APIItem.self, forKey: .stat)
    }

    init(baseStat: Int, stat: APIItem) {
        self.baseStat = baseStat
        self.stat = stat
    }
}
