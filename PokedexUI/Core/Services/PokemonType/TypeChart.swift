import Foundation

/// Immutable Sendable snapshot of the type damage relations chart. Built by
/// `TypeChartLoader` once at app start, then passed by value into off-main
/// consumers (battle engine, AI service).
struct TypeChart: Sendable {
    let attackers: [String: TypeMatchup]

    func multiplier(attacking: String, defenders: [String]) -> Double {
        attackers[attacking]?.multiplier(against: defenders) ?? 1.0
    }
}

/// One attacking type's damage relations, snapshotted from `TypeDetail`.
struct TypeMatchup: Sendable {
    let doubleDamageTo: [String]
    let halfDamageTo: [String]
    let noDamageTo: [String]

    func multiplier(against defenderTypeNames: [String]) -> Double {
        defenderTypeNames.reduce(1.0) { product, defender in
            if noDamageTo.contains(defender) { return 0 }
            if doubleDamageTo.contains(defender) { return product * 2 }
            if halfDamageTo.contains(defender) { return product * 0.5 }
            return product
        }
    }
}

extension TypeChart {
    init(rows: [TypeDetail]) {
        var dict: [String: TypeMatchup] = [:]
        for row in rows {
            dict[row.name] = TypeMatchup(
                doubleDamageTo: row.doubleDamageTo,
                halfDamageTo: row.halfDamageTo,
                noDamageTo: row.noDamageTo
            )
        }
        self.attackers = dict
    }
}
