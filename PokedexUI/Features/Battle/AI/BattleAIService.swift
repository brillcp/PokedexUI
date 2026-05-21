import Foundation
import FoundationModels

/// On-device AI for battle decisions with deterministic fallbacks.
protocol BattleAIServiceProtocol: Sendable {
    /// Pick the best move for this turn.
    func chooseMove(attacker: BattleCombatant, defender: BattleCombatant, moves: [MoveDetail], typeChart: TypeChart, recentMoves: [String], turnNumber: Int) async -> MoveDetail
    /// Pick an opponent id from candidate snapshots.
    func chooseOpponent(player: OpponentCandidateSnapshot, candidates: [OpponentCandidateSnapshot], typeChart: TypeChart?) async -> Int?
    /// Pick a 4-move loadout for a 1v1 battle, informed by what the player chose.
    func chooseLoadout(for fighter: BattleCombatant, against opponent: BattleCombatant, moves: [MoveDetail], playerMoves: [MoveDetail], typeChart: TypeChart) async -> [MoveDetail]
}

/// Battle AI actor backed by on-device Foundation Models.
actor BattleAIService {
    private let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
    private let prompts = BattleAIPromptBuilder()
    private var isGenerating = false
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
        let effectiveness = moves.map { typeChart.multiplier(attacking: $0.typeName, defenders: defender.typeNames) }
        let fallback = BattleAIResponseParser.heuristicMove(
            attacker: attacker,
            defender: defender,
            moves: moves,
            effectiveness: effectiveness,
            recentMoves: recentMoves
        ) ?? first

        let adjust: (MoveDetail) -> MoveDetail = { move in
            let adjusted = BattleAIResponseParser.phaseAdjustedMove(
                move, attacker: attacker, defender: defender, moves: moves, effectiveness: effectiveness
            )
            if adjusted.name != move.name {
                print("[ai] chooseMove: phase override \(move.name) -> \(adjusted.name)")
            }
            return adjusted
        }

        guard isAvailable else { return adjust(fallback) }
        let (prompt, indexMap) = prompts.buildMovePrompt(attacker: attacker, defender: defender, moves: moves, effectiveness: effectiveness, recentMoves: recentMoves, turnNumber: turnNumber)
        print("[llm] chooseMove: \(attacker.name) vs \(defender.name), moves: \(moves.map(\.name)), recent: \(recentMoves)")
        do {
            let raw = try await generate(label: "chooseMove", prompt: prompt, temperature: 0.35, session: moveSession)
            print("[llm] chooseMove: raw response: \(raw.trimmingCharacters(in: .whitespacesAndNewlines))")
            if let shuffledIdx = BattleAIResponseParser.firstInt(in: raw),
               let originalIdx = indexMap[shuffledIdx],
               moves.indices.contains(originalIdx) {
                let modelMove = moves[originalIdx]
                let modelEff = effectiveness[originalIdx]
                if modelEff == 0, fallback.name != modelMove.name {
                    print("[llm] chooseMove: repaired \(modelMove.name) -> \(fallback.name) (immune)")
                    return adjust(fallback)
                }
                print("[llm] chooseMove: shuffled \(shuffledIdx) -> original \(originalIdx) (\(modelMove.name))")
                return adjust(modelMove)
            }
        } catch {
            print("[llm error] \(error.localizedDescription): prompt chars \(prompt.count)")
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
        let fallback = BattleAIResponseParser.heuristicOpponent(player: player, candidates: pool, typeChart: typeChart)
        guard isAvailable else { return fallback }
        let (prompt, indexMap) = prompts.buildOpponentPrompt(player: player, candidates: pool, typeChart: typeChart)
        print("[llm] chooseOpponent: for \(player.name) (\(player.typeNames.joined(separator: "/"))) from \(pool.count) candidates")
        do {
            let raw = try await generate(label: "chooseOpponent", prompt: prompt, temperature: 0.3, session: opponentSession)
            print("[llm] chooseOpponent: raw response: \(raw.trimmingCharacters(in: .whitespacesAndNewlines))")
            if let displayIdx = BattleAIResponseParser.firstInt(in: raw),
               let pokemonId = indexMap[displayIdx] {
                print("[llm] chooseOpponent: index \(displayIdx) -> id \(pokemonId)")
                return pokemonId
            }
        } catch {
            print("[llm error] \(error.localizedDescription): prompt chars \(prompt.count)")
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
        let effectiveness = moves.map { typeChart.multiplier(attacking: $0.typeName, defenders: opponent.typeNames) }
        let fallback = BattleAIResponseParser.assembleOpponentLoadout(
            for: fighter,
            against: opponent,
            moves: moves,
            effectiveness: effectiveness
        )

        let handicap: ([MoveDetail]) -> [MoveDetail] = { picks in
            BattleAIResponseParser.handicapLoadout(
                picks, pool: moves, fighter: fighter, opponent: opponent, typeChart: typeChart
            )
        }

        guard isAvailable else {
            let result = handicap(fallback)
            print("[ai] chooseLoadout: deterministic \(fighter.name) vs \(opponent.name): \(result.map(\.name))")
            return result
        }
        let shortlist = BattleAIResponseParser.loadoutShortlist(
            fighter: fighter, opponent: opponent, moves: moves, effectiveness: effectiveness
        )
        let shortMoves = shortlist.map(\.move)
        let shortEff = shortlist.map(\.eff)
        let playerEff = playerMoves.map { typeChart.multiplier(attacking: $0.typeName, defenders: fighter.typeNames) }
        let (prompt, indexMap) = prompts.buildLoadoutPrompt(
            fighter: fighter,
            opponent: opponent,
            moves: shortMoves,
            effectiveness: shortEff,
            playerMoves: playerMoves,
            playerEffectiveness: playerEff
        )
        print("[llm] chooseLoadout: \(fighter.name) vs \(opponent.name), pool \(moves.count)/\(shortMoves.count)")
        do {
            let raw = try await generate(label: "chooseLoadout", prompt: prompt, temperature: 0.4, session: loadoutSession)
            print("[llm] chooseLoadout: raw response: \(raw.trimmingCharacters(in: .whitespacesAndNewlines))")
            let parsed = BattleAIResponseParser.parseLoadoutIndices(raw, indexMap: indexMap, moves: shortMoves, count: 4)
            if !parsed.isEmpty {
                let filled = BattleAIResponseParser.fillLoadout(
                    seed: parsed, fighter: fighter, opponent: opponent,
                    moves: shortMoves, effectiveness: shortEff, count: 4
                )
                let result = handicap(filled)
                print("[llm] chooseLoadout: picked \(result.map(\.name)) (llm seeded \(parsed.count))")
                return result
            }
        } catch {
            print("[llm error] \(error.localizedDescription): prompt chars \(prompt.count)")
        }
        let result = handicap(fallback)
        print("[ai] chooseLoadout: fallback \(result.map(\.name))")
        return result
    }
}

// MARK: - Private
private extension BattleAIService {
    var isAvailable: Bool {
        if case .available = model.availability { return true }
        return false
    }

    func moveSession() -> LanguageModelSession {
        LanguageModelSession(model: model, instructions: Self.moveInstructions)
    }

    func opponentSession() -> LanguageModelSession {
        LanguageModelSession(model: model, instructions: Self.opponentInstructions)
    }

    func loadoutSession() -> LanguageModelSession {
        LanguageModelSession(model: model, instructions: Self.loadoutInstructions)
    }

    func generate(
        label: String,
        prompt: String,
        temperature: Double,
        session makeSession: () -> LanguageModelSession
    ) async throws -> String {
        let maxAttempts = 3
        var lastError: Error?

        for attempt in 1...maxAttempts {
            await waitForGenerationSlot()
            do {
                defer { isGenerating = false }
                let response = try await makeSession().respond(to: prompt, options: .init(temperature: temperature)).content
                if attempt > 1 {
                    print("[llm] \(label): retry \(attempt) succeeded")
                }
                return response
            } catch {
                isGenerating = false
                lastError = error
            }
        }

        throw lastError ?? CancellationError()
    }

    func waitForGenerationSlot() async {
        while isGenerating {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        isGenerating = true
    }

    static let moveInstructions: String = loadInstructions("BattleAIMoveInstructions", fallback: "You are an expert Pokemon battler.")
    static let opponentInstructions: String = loadInstructions("BattleAIOpponentInstructions", fallback: "You are a Pokemon battle matchmaker.")
    static let loadoutInstructions: String = loadInstructions("BattleAILoadoutInstructions", fallback: "You are an expert Pokemon battler picking a loadout.")

    static func loadInstructions(_ name: String, fallback: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return fallback }
        return text
    }
}
