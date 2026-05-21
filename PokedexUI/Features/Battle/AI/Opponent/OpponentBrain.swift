import BattleKit
import Foundation

/// Wraps `BattleAIServiceProtocol` with a rolling move-history window.
@MainActor
final class OpponentBrain {
    private let service: BattleAIServiceProtocol
    private let historyLimit: Int
    private var history: [String] = []
    private var turnNumber: Int = 0

    init(service: BattleAIServiceProtocol, historyLimit: Int = 4) {
        self.service = service
        self.historyLimit = historyLimit
    }

    func nextMove(
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart
    ) async -> MoveDetail {
        turnNumber += 1
        let pick = await service.chooseMove(
            attacker:    attacker,
            defender:    defender,
            moves:       moves,
            typeChart:   typeChart,
            recentMoves: history,
            turnNumber:  turnNumber
        )
        let final = resolveOverrides(
            pick: pick,
            attacker: attacker,
            defender: defender,
            moves: moves,
            typeChart: typeChart
        )
        record(final.name)
        return final
    }
}

// MARK: - Private
private extension OpponentBrain {
    func resolveOverrides(
        pick: MoveDetail,
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart
    ) -> MoveDetail {
        let pickDamage = DamageCalculator.estimateDamage(
            move: pick, attacker: attacker, defender: defender, typeChart: typeChart
        )
        let pickKOs = pickDamage >= defender.currentHP
        if !pickKOs,
           let killer = DamageCalculator.guaranteedKO(
                attacker: attacker, defender: defender, moves: moves, typeChart: typeChart
           ),
           killer.name != pick.name {
            return killer
        }

        if pick.ailment != "none", (pick.power ?? 0) == 0, defender.status != .none {
            let alternatives = moves.filter { $0.name != pick.name }
            if let best = DamageCalculator.strongestMove(
                attacker: attacker, defender: defender, moves: alternatives, typeChart: typeChart
            ) {
                return best.move
            }
        }

        return pick
    }

    func record(_ name: String) {
        history.append(name)
        if history.count > historyLimit {
            history.removeFirst()
        }
    }
}
