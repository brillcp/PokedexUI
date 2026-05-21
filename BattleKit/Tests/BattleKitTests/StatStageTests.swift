import Testing
@testable import BattleKit

@Suite("Stat stage multiplier")
struct StatStageTests {
    @Test func zeroStageIsNeutral() {
        #expect(statStageMultiplier(0) == 1.0)
    }

    @Test func maxBoostIs4x() {
        #expect(statStageMultiplier(6) == 4.0)
    }

    @Test func maxDropIsQuarter() {
        #expect(statStageMultiplier(-6) == 0.25)
    }

    @Test func clampsAboveSix() {
        #expect(statStageMultiplier(10) == statStageMultiplier(6))
    }

    @Test func clampsBelowNegSix() {
        #expect(statStageMultiplier(-10) == statStageMultiplier(-6))
    }

    @Test func plusOneIs1_5x() {
        #expect(statStageMultiplier(1) == 1.5)
    }

    @Test func minusOneIsTwoThirds() {
        let result = statStageMultiplier(-1)
        #expect(abs(result - 2.0 / 3.0) < 0.001)
    }
}
