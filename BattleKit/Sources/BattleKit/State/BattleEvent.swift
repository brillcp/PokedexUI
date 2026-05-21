import Foundation

/// Discrete event emitted during a turn for sequential animation playback.
public enum BattleEvent: Sendable {
    case used(BattleSide, moveName: String)
    case missed(BattleSide)
    case damaged(BattleSide, amount: Int, effectiveness: Double, crit: Bool)
    case statusApplied(BattleSide, BattleStatus)
    case statusTick(BattleSide, BattleStatus, amount: Int)
    case statChanged(BattleSide, stat: String, delta: Int)
    case healed(BattleSide, amount: Int)
    case recoil(BattleSide, amount: Int)
    case recharging(BattleSide)
    case wokeUp(BattleSide)
    case fastAsleep(BattleSide)
    case fullyParalyzed(BattleSide)
    case lostFocus(BattleSide)
    case fainted(BattleSide)
    case ended(winner: BattleSide?)
}
