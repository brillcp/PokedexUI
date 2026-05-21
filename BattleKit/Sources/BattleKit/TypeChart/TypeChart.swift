import Foundation

/// Immutable Sendable snapshot of the full type damage relations chart.
public struct TypeChart: TypeEffectivenessProviding, Sendable {
    public let attackers: [String: TypeMatchup]

    public init(attackers: [String: TypeMatchup]) {
        self.attackers = attackers
    }

    public func multiplier(attacking: String, defenders: [String]) -> Double {
        attackers[attacking]?.multiplier(against: defenders) ?? 1.0
    }
}

/// One attacking type's damage relations.
public struct TypeMatchup: Sendable {
    public let doubleDamageTo: [String]
    public let halfDamageTo: [String]
    public let noDamageTo: [String]

    public init(doubleDamageTo: [String], halfDamageTo: [String], noDamageTo: [String]) {
        self.doubleDamageTo = doubleDamageTo
        self.halfDamageTo = halfDamageTo
        self.noDamageTo = noDamageTo
    }

    public func multiplier(against defenderTypeNames: [String]) -> Double {
        defenderTypeNames.reduce(1.0) { product, defender in
            if noDamageTo.contains(defender) { return 0 }
            if doubleDamageTo.contains(defender) { return product * 2 }
            if halfDamageTo.contains(defender) { return product * 0.5 }
            return product
        }
    }
}
