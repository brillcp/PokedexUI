import Foundation

/// Stat stage multiplier per the standard Pokemon formula.
/// Stage 0 = 1.0x, +6 = 4.0x, -6 = 0.25x.
public func statStageMultiplier(_ stage: Int) -> Double {
    let s = max(-6, min(6, stage))
    return s >= 0 ? Double(2 + s) / 2.0 : 2.0 / Double(2 - s)
}
