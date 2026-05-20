import SwiftData

/// Fully resolved per-move record: power, accuracy, type, damage class,
/// status ailment, stat-change effects. Battle resolution + AI prompts both
/// read these fields directly. Persisted as a `@Model` and filled either by
/// `MovePrefetcher` (bulk) or `MoveService.requestMove(named:)` (on-demand).
@Model
final class MoveDetail: Decodable, @unchecked Sendable {
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

    private enum CodingKeys: String, CodingKey {
        case name, power, accuracy, pp, priority, type, meta
        case damageClass = "damage_class"
        case statChanges = "stat_changes"
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
    /// How the move's damage is computed. Physical uses atk vs def, special
    /// uses sp.atk vs sp.def, status deals no damage.
    enum DamageClass: String {
        case physical, special, status
    }

    var damageClassKind: DamageClass {
        DamageClass(rawValue: damageClass) ?? .status
    }

    var displayName: String { name.replacingOccurrences(of: "-", with: " ").capitalized }

    /// Damaging moves whose stat changes penalize the USER, not the target.
    private static let selfDebuffMoves: Set<String> = [
        "leaf-storm", "overheat", "draco-meteor", "fleur-cannon", "psycho-boost",
        "close-combat", "superpower", "v-create", "hammer-arm", "ice-hammer",
        "headlong-rush", "clanging-scales"
    ]

    var hasSelfDebuff: Bool { Self.selfDebuffMoves.contains(name) }

    /// Moves that skip the user's next turn after firing.
    private static let rechargeMoves: Set<String> = [
        "blast-burn", "frenzy-plant", "giga-impact", "hydro-cannon",
        "hyper-beam", "meteor-assault", "prismatic-laser",
        "roar-of-time", "rock-wrecker"
    ]

    /// Moves that need a charging turn the engine doesn't implement.
    /// Letting these through gives a free 140-power hit with no drawback.
    private static let chargingMoves: Set<String> = [
        "sky-attack", "solar-beam", "solar-blade", "skull-bash",
        "razor-wind", "fly", "dig", "dive", "bounce", "phantom-force",
        "shadow-force", "geomancy", "meteor-beam"
    ]

    /// Moves that KO the user after firing. The engine doesn't
    /// implement self-destruct; without the blacklist these land as
    /// free 250-power hits with no drawback.
    private static let selfKOMoves: Set<String> = [
        "explosion", "self-destruct", "memento", "healing-wish",
        "lunar-dance", "final-gambit", "misty-explosion"
    ]

    var isRechargeMove: Bool { Self.rechargeMoves.contains(name) }
    var isChargingMove: Bool { Self.chargingMoves.contains(name) }
    var isSelfKOMove: Bool { Self.selfKOMoves.contains(name) }

    /// `true` when the battle engine can meaningfully resolve this move.
    /// Filters out protection, field effects, charging moves, and other
    /// unimplemented mechanics so they never appear in the battle move picker.
    var isBattleReady: Bool {
        if isChargingMove { return false }
        if isSelfKOMove { return false }
        if (power ?? 0) > 0 { return true }
        if healing > 0 || name == "rest" { return true }
        if !statChangeNames.isEmpty { return true }
        if ailment != "none" { return true }
        return false
    }
}
