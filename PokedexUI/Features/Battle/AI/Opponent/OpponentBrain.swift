import BattleKit
import Foundation

/// Wraps `BattleAIServiceProtocol` with rolling move history and a turn
/// counter so the service can score recency penalties and embed turn
/// numbers in prompts. Move-selection corrections live in
/// ``MoveStrategy/adjust(pick:attacker:defender:moves:typeChart:fallback:)``;
/// this type is pure stateful glue.
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
        defenderMoves: [MoveDetail],
        defenderSeenMoves: [String],
        typeChart: TypeChart
    ) async -> MoveDetail {
        turnNumber += 1
        let pick = await service.chooseMove(
            attacker:          attacker,
            defender:          defender,
            moves:             moves,
            defenderMoves:     defenderMoves,
            defenderSeenMoves: defenderSeenMoves,
            typeChart:         typeChart,
            recentMoves:       history,
            turnNumber:        turnNumber
        )
        record(pick.name)
        return pick
    }
}

// MARK: - Private
private extension OpponentBrain {
    func record(_ name: String) {
        history.append(name)
        if history.count > historyLimit {
            history.removeFirst()
        }
    }
}
