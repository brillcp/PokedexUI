import BattleKit
import Foundation

/// On-device AI for battle decisions with deterministic fallbacks.
protocol BattleAIServiceProtocol: Sendable {
    /// Pick the best move for this turn.
    func chooseMove(attacker: BattleCombatant, defender: BattleCombatant, moves: [MoveDetail], typeChart: TypeChart, recentMoves: [String], turnNumber: Int) async -> MoveDetail
    /// Pick an opponent id from candidate snapshots.
    func chooseOpponent(player: OpponentCandidateSnapshot, candidates: [OpponentCandidateSnapshot], typeChart: TypeChart?) async -> Int?
    /// Pick a 4-move loadout for a 1v1 battle, informed by what the player chose.
    func chooseLoadout(for fighter: BattleCombatant, against opponent: BattleCombatant, moves: [MoveDetail], playerMoves: [MoveDetail], typeChart: TypeChart) async -> [MoveDetail]
}

/// Thin façade over an on-device language model client plus per-decision
/// strategy and prompt helpers. Each public method:
/// 1. Asks the relevant `*Strategy` for a deterministic fallback.
/// 2. Bails to that fallback if the model is unavailable.
/// 3. Builds the prompt, runs generation, parses the response.
/// 4. Hands the parsed pick back to the strategy for post-pick adjustment.
actor BattleAIService {
    private let client = LanguageModelClient()
}

// MARK: - BattleAIServiceProtocol
extension BattleAIService: BattleAIServiceProtocol {

    func chooseMove(
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart,
        recentMoves: [String],
        turnNumber: Int
    ) async -> MoveDetail {
        guard let first = moves.first else { return MoveDetail(name: "tackle") }
        let fallback = MoveStrategy.heuristicPick(
            attacker: attacker, defender: defender, moves: moves, typeChart: typeChart, recentMoves: recentMoves
        ) ?? first

        let adjust: (MoveDetail) -> MoveDetail = { pick in
            let adjusted = MoveStrategy.phaseAdjust(
                pick: pick, attacker: attacker, defender: defender, moves: moves, typeChart: typeChart
            )
            if adjusted.name != pick.name {
                print("[ai] chooseMove: phase override \(pick.name) -> \(adjusted.name)")
            }
            return adjusted
        }

        guard await client.isAvailable else { return adjust(fallback) }
        let output = MovePrompt.build(
            attacker: attacker, defender: defender, moves: moves, typeChart: typeChart, turnNumber: turnNumber
        )
        print("[llm] chooseMove: \(attacker.name) vs \(defender.name), moves: \(moves.map(\.name)), recent: \(recentMoves)")
        do {
            let raw = try await client.generate(
                label: "chooseMove", prompt: output.prompt, temperature: 0.35, instructions: .move
            )
            print("[llm] chooseMove: raw response: \(raw.trimmingCharacters(in: .whitespacesAndNewlines))")
            if let pick = MovePrompt.parsePick(raw: raw, indexMap: output.indexMap, moves: moves) {
                let repaired = MoveStrategy.immuneRepair(pick: pick, defender: defender, typeChart: typeChart, fallback: fallback)
                if repaired.name != pick.name {
                    print("[llm] chooseMove: repaired \(pick.name) -> \(repaired.name) (immune)")
                }
                return adjust(repaired)
            }
        } catch {
            print("[llm error] \(error.localizedDescription): prompt chars \(output.prompt.count)")
        }
        return adjust(fallback)
    }

    func chooseOpponent(
        player: OpponentCandidateSnapshot,
        candidates: [OpponentCandidateSnapshot],
        typeChart: TypeChart?
    ) async -> Int? {
        let pool = candidates.filter { $0.id != player.id }
        guard !pool.isEmpty else { return nil }
        let fallback = OpponentStrategy.heuristicPick(player: player, candidates: pool, typeChart: typeChart)
        guard await client.isAvailable else { return fallback }
        let output = OpponentPrompt.build(player: player, candidates: pool, typeChart: typeChart)
        print("[llm] chooseOpponent: for \(player.name) (\(player.typeNames.joined(separator: "/"))) from \(pool.count) candidates")
        do {
            let raw = try await client.generate(
                label: "chooseOpponent", prompt: output.prompt, temperature: 0.3, instructions: .opponent
            )
            print("[llm] chooseOpponent: raw response: \(raw.trimmingCharacters(in: .whitespacesAndNewlines))")
            if let pokemonId = OpponentPrompt.parsePick(raw: raw, indexMap: output.indexMap) {
                print("[llm] chooseOpponent: -> id \(pokemonId)")
                return pokemonId
            }
        } catch {
            print("[llm error] \(error.localizedDescription): prompt chars \(output.prompt.count)")
        }
        return fallback
    }

    func chooseLoadout(
        for fighter: BattleCombatant,
        against opponent: BattleCombatant,
        moves: [MoveDetail],
        playerMoves: [MoveDetail],
        typeChart: TypeChart
    ) async -> [MoveDetail] {
        guard moves.count > 4 else { return moves }
        let fallback = LoadoutStrategy.assemble(
            fighter: fighter, opponent: opponent, moves: moves, typeChart: typeChart
        )

        let balance: ([MoveDetail]) -> [MoveDetail] = { picks in
            let composed = LoadoutStrategy.enforceComposition(
                picks, pool: moves, fighter: fighter, opponent: opponent, typeChart: typeChart
            )
            return LoadoutStrategy.handicap(
                composed, pool: moves, fighter: fighter, opponent: opponent, typeChart: typeChart
            )
        }

        guard await client.isAvailable else {
            let result = balance(fallback)
            print("[ai] chooseLoadout: deterministic \(fighter.name) vs \(opponent.name): \(result.map(\.name))")
            return result
        }
        let shortMoves = LoadoutStrategy.shortlist(
            fighter: fighter, opponent: opponent, moves: moves, typeChart: typeChart
        )
        let output = LoadoutPrompt.build(
            fighter: fighter, opponent: opponent, moves: shortMoves, playerMoves: playerMoves, typeChart: typeChart
        )
        print("[llm] chooseLoadout: \(fighter.name) vs \(opponent.name), pool \(moves.count)/\(shortMoves.count)")
        do {
            let raw = try await client.generate(
                label: "chooseLoadout", prompt: output.prompt, temperature: 0.4, instructions: .loadout
            )
            print("[llm] chooseLoadout: raw response: \(raw.trimmingCharacters(in: .whitespacesAndNewlines))")
            let parsed = LoadoutPrompt.parsePicks(raw: raw, indexMap: output.indexMap, moves: shortMoves)
            if !parsed.isEmpty {
                let filled = LoadoutStrategy.fill(
                    seed: parsed, fighter: fighter, opponent: opponent,
                    moves: shortMoves, typeChart: typeChart, count: 4
                )
                let result = balance(filled)
                print("[llm] chooseLoadout: picked \(result.map(\.name)) (llm seeded \(parsed.count))")
                return result
            }
        } catch {
            print("[llm error] \(error.localizedDescription): prompt chars \(output.prompt.count)")
        }
        let result = balance(fallback)
        print("[ai] chooseLoadout: fallback \(result.map(\.name))")
        return result
    }
}
