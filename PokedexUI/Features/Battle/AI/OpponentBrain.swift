import Foundation

/// Wraps `BattleAIServiceProtocol` with a rolling move-history window.
@MainActor
final class OpponentBrain {
    private let service: BattleAIServiceProtocol
    private let historyLimit: Int
    private var history: [String] = []

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
        if history.isEmpty,
           Double.random(in: 0..<1) < Self.openerChance,
           let opener = pickOpener(attacker: attacker, defender: defender, moves: moves) {
            record(opener.name)
            return opener
        }
        let pick = await service.chooseMove(
            attacker:    attacker,
            defender:    defender,
            moves:       moves,
            typeChart:   typeChart,
            recentMoves: history
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

private extension OpponentBrain {
    static let openerChance = 0.5

    /// Pick a viable opening status/setup move on turn 1, or nil if nothing useful is available.
    func pickOpener(
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail]
    ) -> MoveDetail? {
        let candidates = moves.filter { move in
            guard (move.power ?? 0) == 0 else { return false }
            if move.name == "rest" { return false }
            if move.ailment != "none" {
                return defender.status == .none && move.ailment != "confusion"
            }
            if !move.statChangeNames.isEmpty {
                return move.statChangeDeltas.contains { $0 != 0 }
            }
            if move.healing > 0 {
                return attacker.currentHP < attacker.maxHP
            }
            return false
        }
        return candidates.randomElement()
    }

    /// Apply post-LLM safety nets: take a guaranteed KO when offered, avoid wasting status on an already-statused target.
    func resolveOverrides(
        pick: MoveDetail,
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart
    ) -> MoveDetail {
        let pickDamage = BattleAIResponseParser.estimatedDamage(
            move: pick,
            attacker: attacker,
            defender: defender,
            typeChart: typeChart
        )
        let pickKOs = pickDamage >= Double(defender.currentHP)
        if !pickKOs,
           let killer = BattleAIResponseParser.guaranteedKO(
                attacker: attacker,
                defender: defender,
                moves: moves,
                typeChart: typeChart
           ),
           killer.name != pick.name {
            return killer
        }

        // Don't waste a status move on an already-statused target.
        if pick.ailment != "none", (pick.power ?? 0) == 0, defender.status != .none {
            let replacement = moves
                .filter { $0.name != pick.name }
                .max { lhs, rhs in
                    BattleAIResponseParser.estimatedDamage(
                        move: lhs,
                        attacker: attacker,
                        defender: defender,
                        typeChart: typeChart
                    ) < BattleAIResponseParser.estimatedDamage(
                        move: rhs,
                        attacker: attacker,
                        defender: defender,
                        typeChart: typeChart
                    )
                }
            if let replacement, BattleAIResponseParser.estimatedDamage(
                move: replacement,
                attacker: attacker,
                defender: defender,
                typeChart: typeChart
            ) > 0 {
                return replacement
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
