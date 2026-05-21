import BattleKit

// Re-export BattleKit types so existing files see them without adding imports.
typealias BattleSide = BattleKit.BattleSide
typealias BattleStatus = BattleKit.BattleStatus
typealias BattlePhase = BattleKit.BattlePhase
typealias BattleEvent = BattleKit.BattleEvent
typealias BattleCombatant = BattleKit.BattleCombatant
typealias BattleState = BattleKit.BattleState
typealias BattleMoveSnapshot = BattleKit.BattleMoveSnapshot
typealias BattleMoveData = BattleKit.BattleMoveData
typealias BattlePokemonData = BattleKit.BattlePokemonData
typealias MoveClassification = BattleKit.MoveClassification

func statStageMultiplier(_ stage: Int) -> Double {
    BattleKit.statStageMultiplier(stage)
}
