import Testing
@testable import BattleKit

@Suite("Type chart multiplier")
struct TypeChartTests {
    static let chart = TypeChart(attackers: [
        "fire": TypeMatchup(
            doubleDamageTo: ["grass", "ice"],
            halfDamageTo: ["water", "fire"],
            noDamageTo: []
        ),
        "water": TypeMatchup(
            doubleDamageTo: ["fire"],
            halfDamageTo: ["grass", "water"],
            noDamageTo: []
        ),
        "normal": TypeMatchup(
            doubleDamageTo: [],
            halfDamageTo: [],
            noDamageTo: ["ghost"]
        ),
    ])

    @Test func superEffective() {
        let mult = Self.chart.multiplier(attacking: "fire", defenders: ["grass"])
        #expect(mult == 2.0)
    }

    @Test func notVeryEffective() {
        let mult = Self.chart.multiplier(attacking: "fire", defenders: ["water"])
        #expect(mult == 0.5)
    }

    @Test func immune() {
        let mult = Self.chart.multiplier(attacking: "normal", defenders: ["ghost"])
        #expect(mult == 0.0)
    }

    @Test func dualTypeSuperEffective() {
        let mult = Self.chart.multiplier(attacking: "fire", defenders: ["grass", "ice"])
        #expect(mult == 4.0)
    }

    @Test func dualTypeMixed() {
        let mult = Self.chart.multiplier(attacking: "fire", defenders: ["grass", "water"])
        #expect(mult == 1.0)
    }

    @Test func unknownAttackerDefaultsToNeutral() {
        let mult = Self.chart.multiplier(attacking: "fairy", defenders: ["fire"])
        #expect(mult == 1.0)
    }

    @Test func bestSTABMultiplierMaxesAttackers() {
        // Fire/water attacker vs grass: fire 2x, water 0.5x → max 2.0
        let result = Self.chart.bestSTABMultiplier(attackerTypes: ["fire", "water"], defenderTypes: ["grass"])
        #expect(result == 2.0)
    }

    @Test func bestSTABMultiplierPicksImmunity() {
        // Normal attacker vs ghost: 0x. Single type, max is still 0.
        let result = Self.chart.bestSTABMultiplier(attackerTypes: ["normal"], defenderTypes: ["ghost"])
        #expect(result == 0.0)
    }

    @Test func bestSTABMultiplierEmptyAttackersReturnsNeutral() {
        let result = Self.chart.bestSTABMultiplier(attackerTypes: [], defenderTypes: ["grass"])
        #expect(result == 1.0)
    }
}
