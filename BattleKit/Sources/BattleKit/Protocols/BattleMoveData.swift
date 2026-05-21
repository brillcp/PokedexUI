import Foundation

/// Properties the battle engine reads from a move.
///
/// Conformers include the concrete ``BattleMoveSnapshot`` shipped with
/// this package and any app-side persistence model (e.g. a SwiftData
/// `@Model`) that satisfies the same shape. The protocol intentionally
/// omits `Sendable` so non-Sendable model classes can conform.
public protocol BattleMoveData {
    var name: String { get }
    var displayName: String { get }
    var power: Int? { get }
    var accuracy: Int? { get }
    var priority: Int { get }
    var damageClass: String { get }
    var typeName: String { get }
    var ailment: String { get }
    var ailmentChance: Int { get }
    var drain: Int { get }
    var healing: Int { get }
    var effectChance: Int? { get }
    var statChangeNames: [String] { get }
    var statChangeDeltas: [Int] { get }
    var isRechargeMove: Bool { get }
    var hasSelfDebuff: Bool { get }
}

public extension BattleMoveData {
    var damageClassKind: DamageClass {
        DamageClass(rawValue: damageClass) ?? .status
    }

    var loadoutCategory: String {
        if (power ?? 0) > 0 { return "DMG" }
        if statChangeDeltas.contains(where: { $0 > 0 }) { return "BOOST" }
        if ailment != "none" || statChangeDeltas.contains(where: { $0 < 0 }) { return "DISRUPT" }
        if healing > 0 || name == "rest" { return "HEAL" }
        return "OTHER"
    }

    var isBattleReady: Bool {
        if MoveClassification.chargingMoves.contains(name) { return false }
        if MoveClassification.selfKOMoves.contains(name) { return false }
        if (power ?? 0) > 0 { return true }
        if healing > 0 || name == "rest" { return true }
        if !statChangeNames.isEmpty { return true }
        if ailment != "none" { return true }
        return false
    }
}
