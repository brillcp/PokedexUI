import Foundation
import FoundationModels

/// On-device AI for battle decisions with deterministic fallbacks.
protocol BattleAIServiceProtocol: Sendable {
    /// Pick the best move for this turn.
    func chooseMove(attacker: BattleCombatant, defender: BattleCombatant, moves: [MoveDetail], typeChart: TypeChart, recentMoves: [String]) async -> MoveDetail
    /// Pick an opponent id from candidate snapshots.
    func chooseOpponent(player: OpponentCandidateSnapshot, candidates: [OpponentCandidateSnapshot], typeChart: TypeChart?) async -> Int?
    /// Pick a 4-move loadout for a 1v1 battle.
    func chooseLoadout(for fighter: BattleCombatant, against opponent: BattleCombatant, moves: [MoveDetail], typeChart: TypeChart) async -> [MoveDetail]
}

/// Battle AI actor backed by on-device Foundation Models.
actor BattleAIService: BattleAIServiceProtocol {
    private let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
    private let prompts = BattleAIPromptBuilder()
    private var isGenerating = false

    func chooseMove(
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart,
        recentMoves: [String]
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
        guard isAvailable else { return fallback }
        let (prompt, indexMap) = prompts.buildMovePrompt(attacker: attacker, defender: defender, moves: moves, effectiveness: effectiveness, recentMoves: recentMoves)
        print("[llm] chooseMove: \(attacker.name) vs \(defender.name), moves: \(moves.map(\.name)), recent: \(recentMoves)")
        do {
            let raw = try await generate(label: "chooseMove", prompt: prompt, temperature: 0.35, session: moveSession)
            print("[llm] chooseMove: raw response: \(raw.trimmingCharacters(in: .whitespacesAndNewlines))")
            if let shuffledIdx = BattleAIResponseParser.firstInt(in: raw),
               let originalIdx = indexMap[shuffledIdx],
               moves.indices.contains(originalIdx) {
                let modelMove = moves[originalIdx]
                let modelEff = effectiveness[originalIdx]
                // Only override immune picks
                if modelEff == 0, fallback.name != modelMove.name {
                    print("[llm] chooseMove: repaired \(modelMove.name) -> \(fallback.name) (immune)")
                    return fallback
                }
                print("[llm] chooseMove: shuffled \(shuffledIdx) -> original \(originalIdx) (\(modelMove.name))")
                return modelMove
            }
        } catch { logGenerationError(error, label: "chooseMove", prompt: prompt) }
        return fallback
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
        let prompt = prompts.buildOpponentPrompt(player: player, candidates: pool, typeChart: typeChart)
        print("[llm] chooseOpponent: for \(player.name) (\(player.typeNames.joined(separator: "/"))) from \(pool.count) candidates")
        do {
            let raw = try await generate(label: "chooseOpponent", prompt: prompt, temperature: 0.5, session: opponentSession)
            print("[llm] chooseOpponent: raw response: \(raw.trimmingCharacters(in: .whitespacesAndNewlines))")
            if let id = BattleAIResponseParser.firstInt(in: raw), pool.contains(where: { $0.id == id }) {
                let repaired = BattleAIResponseParser.repairedOpponent(
                    modelId: id,
                    player: player,
                    candidates: pool,
                    typeChart: typeChart
                ) ?? id
                if repaired != id {
                    print("[llm] chooseOpponent: repaired id \(id) -> \(repaired)")
                }
                print("[llm] chooseOpponent: resolved to id \(repaired)")
                return repaired
            }
        } catch { logGenerationError(error, label: "chooseOpponent", prompt: prompt) }
        return fallback
    }

    func chooseLoadout(
        for fighter: BattleCombatant,
        against opponent: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart
    ) async -> [MoveDetail] {
        let size = 4
        guard moves.count > size else { return moves }
        let effectiveness = moves.map { typeChart.multiplier(attacking: $0.typeName, defenders: opponent.typeNames) }
        let promptMoves = BattleAIResponseParser.rankedMoveSample(
            for: fighter,
            against: opponent,
            moves: moves,
            effectiveness: effectiveness,
            count: 40
        )
        let promptEffectiveness = promptMoves.map { typeChart.multiplier(attacking: $0.typeName, defenders: opponent.typeNames) }
        let fallback = BattleAIResponseParser.heuristicLoadout(
            for: fighter,
            against: opponent,
            moves: moves,
            effectiveness: effectiveness,
            count: size
        )
        guard isAvailable else { return fallback }
        let prompt = prompts.buildLoadoutPrompt(fighter: fighter, opponent: opponent, moves: promptMoves, effectiveness: promptEffectiveness, loadoutSize: size)
        print("[llm] chooseLoadout: \(fighter.name) vs \(opponent.name), pool size \(promptMoves.count)/\(moves.count)")
        do {
            let raw = try await generate(label: "chooseLoadout", prompt: prompt, temperature: 0.4, session: loadoutSession)
            print("[llm] chooseLoadout: raw response: \(raw.trimmingCharacters(in: .whitespacesAndNewlines))")
            let indices = BattleAIResponseParser.intsOnLastLine(of: raw)
            print("[llm] chooseLoadout: parsed indices \(indices)")
            let result = BattleAIResponseParser.repairedLoadout(
                indices: indices,
                from: promptMoves,
                fighter: fighter,
                opponent: opponent,
                effectiveness: promptEffectiveness,
                size: size
            )
            print("[llm] chooseLoadout: final loadout: \(result.map(\.name))")
            return result
        } catch { logGenerationError(error, label: "chooseLoadout", prompt: prompt) }
        return fallback
    }

}

private extension BattleAIService {
    var isAvailable: Bool {
        if case .available = model.availability { return true }
        return false
    }

    func moveSession() -> LanguageModelSession {
        LanguageModelSession(model: model, instructions: Self.moveInstructions)
    }

    func loadoutSession() -> LanguageModelSession {
        LanguageModelSession(model: model, instructions: Self.loadoutInstructions)
    }

    func opponentSession() -> LanguageModelSession {
        LanguageModelSession(model: model, instructions: Self.opponentInstructions)
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
                guard attempt < maxAttempts, isRetryableModelError(error) else { throw error }
                print("[llm] \(label): retrying after model manager error (attempt \(attempt) of \(maxAttempts))")
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 350_000_000)
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
    static let loadoutInstructions: String = loadInstructions("BattleAILoadoutInstructions", fallback: "You are an expert Pokemon teambuilder.")
    static let opponentInstructions: String = loadInstructions("BattleAIOpponentInstructions", fallback: "You are a Pokemon battle matchmaker.")

    static func loadInstructions(_ name: String, fallback: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return fallback }
        return text
    }

    func logGenerationError(_ error: Error, label: String, prompt: String) {
        print("[llm error] \(label): prompt chars \(prompt.count)")
        for line in describe(error as NSError) {
            print("[llm error] \(label): \(line)")
        }
    }

    func describe(_ error: NSError, depth: Int = 0) -> [String] {
        let indent = String(repeating: "  ", count: depth)
        var lines = [
            "\(indent)\(error.domain) code \(error.code): \(error.localizedDescription)"
        ]

        if let reason = error.userInfo[NSLocalizedFailureReasonErrorKey] as? String {
            lines.append("\(indent)reason: \(reason)")
        }
        if let recovery = error.userInfo[NSLocalizedRecoverySuggestionErrorKey] as? String {
            lines.append("\(indent)recovery: \(recovery)")
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            lines.append("\(indent)underlying:")
            lines += describe(underlying, depth: depth + 1)
        }
        if let underlying = error.userInfo[NSMultipleUnderlyingErrorsKey] as? [NSError] {
            for (index, nested) in underlying.enumerated() {
                lines.append("\(indent)underlying[\(index)]:")
                lines += describe(nested, depth: depth + 1)
            }
        }

        return lines
    }

    func isRetryableModelError(_ error: Error) -> Bool {
        containsModelManagerError(error as NSError, code: 1026)
    }

    func containsModelManagerError(_ error: NSError, code: Int) -> Bool {
        if error.domain == "ModelManagerServices.ModelManagerError", error.code == code {
            return true
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError,
           containsModelManagerError(underlying, code: code) {
            return true
        }
        if let underlying = error.userInfo[NSMultipleUnderlyingErrorsKey] as? [NSError] {
            return underlying.contains { containsModelManagerError($0, code: code) }
        }
        return false
    }
}
