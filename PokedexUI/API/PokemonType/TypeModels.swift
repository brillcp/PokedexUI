import SwiftData

@Model
final class TypeDetail: Decodable, @unchecked Sendable {
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

// MARK: - Effectiveness lookup
extension TypeDetail {
    /// Returns the damage multiplier when this attacking type hits a defender with the given type names.
    /// Multiplies per defender type and clamps at 0 if any defender type is fully immune.
    func multiplier(against defenderTypeNames: [String]) -> Double {
        defenderTypeNames.reduce(1.0) { product, defender in
            if noDamageTo.contains(defender) { return 0 }
            if doubleDamageTo.contains(defender) { return product * 2 }
            if halfDamageTo.contains(defender) { return product * 0.5 }
            return product
        }
    }
}
