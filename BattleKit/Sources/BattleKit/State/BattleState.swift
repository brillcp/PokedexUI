import Foundation

/// Snapshot of an in-flight battle. Mutated by `BattleEngine.resolveRound`
/// once per turn.
public struct BattleState: Sendable {
    public var player: BattleCombatant
    public var opponent: BattleCombatant
    var phase: BattlePhase = .selectingMove

    public init(player: BattleCombatant, opponent: BattleCombatant) {
        self.player = player
        self.opponent = opponent
    }
}
