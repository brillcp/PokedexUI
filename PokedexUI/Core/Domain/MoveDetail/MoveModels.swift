import PokeBattleKit
import SwiftData

/// Fully resolved per-move record persisted as a `@Model`.
@Model
final class MoveDetail: Decodable {
    @Attribute(.unique) var name: String
    var power: Int? = nil
    var accuracy: Int? = nil
    var pp: Int? = nil
    var priority: Int = 0
    var damageClass: String = "status"
    var typeName: String = "normal"
    var ailment: String = "none"
    var ailmentChance: Int = 0
    var drain: Int = 0
    var healing: Int = 0
    var category: String = "damage"
    var statChangeNames: [String] = []
    var statChangeDeltas: [Int] = []
    var effectChance: Int? = nil

    private enum CodingKeys: String, CodingKey {
        case name, power, accuracy, pp, priority, type, meta
        case damageClass = "damage_class"
        case statChanges = "stat_changes"
        case effectChance = "effect_chance"
    }

    private enum MetaKeys: String, CodingKey {
        case ailment
        case ailmentChance = "ailment_chance"
        case drain, healing, category
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try c.decode(String.self, forKey: .name)
        self.power = try c.decodeIfPresent(Int.self, forKey: .power)
        self.accuracy = try c.decodeIfPresent(Int.self, forKey: .accuracy)
        self.pp = try c.decodeIfPresent(Int.self, forKey: .pp)
        self.priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 0

        let damageClassRef = try c.decodeIfPresent(NamedRef.self, forKey: .damageClass)
        self.damageClass = damageClassRef?.name ?? "status"

        let typeRef = try c.decodeIfPresent(NamedRef.self, forKey: .type)
        self.typeName = typeRef?.name ?? "normal"

        if let metaContainer = try? c.nestedContainer(keyedBy: MetaKeys.self, forKey: .meta) {
            let ailmentRef = try metaContainer.decodeIfPresent(NamedRef.self, forKey: .ailment)
            self.ailment = ailmentRef?.name ?? "none"
            self.ailmentChance = try metaContainer.decodeIfPresent(Int.self, forKey: .ailmentChance) ?? 0
            self.drain = try metaContainer.decodeIfPresent(Int.self, forKey: .drain) ?? 0
            self.healing = try metaContainer.decodeIfPresent(Int.self, forKey: .healing) ?? 0
            let categoryRef = try metaContainer.decodeIfPresent(NamedRef.self, forKey: .category)
            self.category = categoryRef?.name ?? "damage"
        }

        let statChanges = try c.decodeIfPresent([StatChangeDTO].self, forKey: .statChanges) ?? []
        self.statChangeNames = statChanges.map { $0.stat.name }
        self.statChangeDeltas = statChanges.map { $0.change }
        self.effectChance = try c.decodeIfPresent(Int.self, forKey: .effectChance)
    }

    init(name: String) {
        self.name = name
    }
}

private struct NamedRef: Decodable { let name: String }

private struct StatChangeDTO: Decodable {
    let change: Int
    let stat: NamedRef
}

extension MoveDetail {
    var displayName: String { name.replacingOccurrences(of: "-", with: " ").capitalized }

    var hasSelfDebuff: Bool { MoveClassification.selfDebuffMoves.contains(name) }
    var isRechargeMove: Bool { MoveClassification.rechargeMoves.contains(name) }
}

// MARK: - BattleMoveData

extension MoveDetail: BattleMoveData {
    func snapshot() -> BattleMoveSnapshot {
        BattleMoveSnapshot(from: self)
    }
}
