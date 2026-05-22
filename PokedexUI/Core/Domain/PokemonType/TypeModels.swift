import SwiftData

/// `/type/{id}` damage relations for one of the 18 elemental types. Persisted
/// as a `@Model` and read by `TypeChartLoader`, which snapshots it into a
/// value-type `TypeChart` for off-main lookups.
@Model
final class TypeDetail: Decodable {
    @Attribute(.unique) var name: String
    var doubleDamageTo: [String] = []
    var doubleDamageFrom: [String] = []
    var halfDamageTo: [String] = []
    var halfDamageFrom: [String] = []
    var noDamageTo: [String] = []
    var noDamageFrom: [String] = []

    private enum CodingKeys: String, CodingKey {
        case name
        case damageRelations = "damage_relations"
    }

    private enum DamageRelationKeys: String, CodingKey {
        case doubleDamageTo = "double_damage_to"
        case doubleDamageFrom = "double_damage_from"
        case halfDamageTo = "half_damage_to"
        case halfDamageFrom = "half_damage_from"
        case noDamageTo = "no_damage_to"
        case noDamageFrom = "no_damage_from"
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try c.decode(String.self, forKey: .name)
        let r = try c.nestedContainer(keyedBy: DamageRelationKeys.self, forKey: .damageRelations)
        self.doubleDamageTo = (try r.decodeIfPresent([NamedRef].self, forKey: .doubleDamageTo) ?? []).map(\.name)
        self.doubleDamageFrom = (try r.decodeIfPresent([NamedRef].self, forKey: .doubleDamageFrom) ?? []).map(\.name)
        self.halfDamageTo = (try r.decodeIfPresent([NamedRef].self, forKey: .halfDamageTo) ?? []).map(\.name)
        self.halfDamageFrom = (try r.decodeIfPresent([NamedRef].self, forKey: .halfDamageFrom) ?? []).map(\.name)
        self.noDamageTo = (try r.decodeIfPresent([NamedRef].self, forKey: .noDamageTo) ?? []).map(\.name)
        self.noDamageFrom = (try r.decodeIfPresent([NamedRef].self, forKey: .noDamageFrom) ?? []).map(\.name)
    }

    init(name: String) {
        self.name = name
    }
}

private struct NamedRef: Decodable { let name: String }
