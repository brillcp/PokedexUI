import Foundation

/// Immutable Sendable snapshot of the type damage relations chart. Built by
/// `TypeChartLoader` once at app start, then passed by value into any
/// off-main consumer (battle engine, AI service, etc.) so type lookups
/// never need to bounce onto the main actor.
///
/// `TypeDetail` itself is a SwiftData `@Model` and lives on its
/// `ModelContext`'s actor; we snapshot the relations into plain `String`
/// arrays here so callers can read freely from any concurrency context.
struct TypeChart: Sendable {
    let attackers: [String: TypeMatchup]

    /// Multiplier for an attacking type vs one or two defender types. Returns
    /// 1.0 for an unknown attacker (defensive fallback during initial app
    /// load when the chart isn't fully populated yet).
    func multiplier(attacking: String, defenders: [String]) -> Double {
        attackers[attacking]?.multiplier(against: defenders) ?? 1.0
    }
}

/// One attacking type's damage relations, snapshotted from `TypeDetail`.
struct TypeMatchup: Sendable {
    let doubleDamageTo: [String]
    let halfDamageTo: [String]
    let noDamageTo: [String]

    /// Multiplies per defender type, clamps at 0 if any defender is immune.
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
    /// Build a snapshot from the SwiftData `TypeDetail` rows. Must be called
    /// from the model's actor (typically `@MainActor`) since `TypeDetail`
    /// property reads are isolated.
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
