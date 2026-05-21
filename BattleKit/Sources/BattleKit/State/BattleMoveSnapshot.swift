import Foundation

/// Immutable, Sendable value copy of a move for use inside the engine.
public struct BattleMoveSnapshot: BattleMoveData, Hashable, Sendable {
    public let name: String
    public let displayName: String
    public let power: Int?
    public let accuracy: Int?
    public let priority: Int
    public let damageClass: String
    public let typeName: String
    public let ailment: String
    public let ailmentChance: Int
    public let drain: Int
    public let healing: Int
    public let effectChance: Int?
    public let statChangeNames: [String]
    public let statChangeDeltas: [Int]
    public let isRechargeMove: Bool
    public let hasSelfDebuff: Bool

    public init(
        name: String,
        displayName: String,
        power: Int?,
        accuracy: Int?,
        priority: Int,
        damageClass: String,
        typeName: String,
        ailment: String,
        ailmentChance: Int,
        drain: Int,
        healing: Int,
        effectChance: Int?,
        statChangeNames: [String],
        statChangeDeltas: [Int],
        isRechargeMove: Bool,
        hasSelfDebuff: Bool
    ) {
        self.name = name
        self.displayName = displayName
        self.power = power
        self.accuracy = accuracy
        self.priority = priority
        self.damageClass = damageClass
        self.typeName = typeName
        self.ailment = ailment
        self.ailmentChance = ailmentChance
        self.drain = drain
        self.healing = healing
        self.effectChance = effectChance
        self.statChangeNames = statChangeNames
        self.statChangeDeltas = statChangeDeltas
        self.isRechargeMove = isRechargeMove
        self.hasSelfDebuff = hasSelfDebuff
    }

    /// Build a snapshot from any `BattleMoveData` conformer.
    public init(from source: some BattleMoveData) {
        self.name = source.name
        self.displayName = source.displayName
        self.power = source.power
        self.accuracy = source.accuracy
        self.priority = source.priority
        self.damageClass = source.damageClass
        self.typeName = source.typeName
        self.ailment = source.ailment
        self.ailmentChance = source.ailmentChance
        self.drain = source.drain
        self.healing = source.healing
        self.effectChance = source.effectChance
        self.statChangeNames = source.statChangeNames
        self.statChangeDeltas = source.statChangeDeltas
        self.isRechargeMove = source.isRechargeMove
        self.hasSelfDebuff = source.hasSelfDebuff
    }
}
