import Foundation
import FoundationModels

/// On-device AI brain for the battle screen. Two responsibilities:
///   1. Pick the opponent's move each turn ("expert pokemon player, what should
///      Charizard do against Blastoise at low HP?").
///   2. Pick a worthy opponent when the player taps "smart opponent" in the
///      opponent picker.
///
/// Both calls degrade gracefully: if Apple Intelligence isn't available on the
/// device, if the session is busy, or if the model returns garbage, we fall
/// back to deterministic heuristics (random move / random opponent) so the
/// battle UI never blocks waiting on the model.
///
/// Inspired by Borealis' `AuroraPredictionService` — same `LanguageModelSession`
/// pattern with instructions loaded from a markdown file and a `@Generable`
/// output struct for structured decoding.
protocol BattleAIServiceProtocol: Sendable {
    /// Pick the opponent's next move given the current battle snapshot.
    /// Falls back to a random move on any failure.
    func chooseMove(
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail]
    ) async -> MoveDetail

    /// Pick an "interesting" opponent for the player from a candidate roster.
    /// Falls back to a random non-self opponent on any failure.
    func chooseOpponent(
        for player: PokemonSummary,
        candidates: [PokemonSummary]
    ) async -> PokemonSummary
}

actor BattleAIService: BattleAIServiceProtocol {
    private let session: LanguageModelSession
    private let model: SystemLanguageModel
    private let promptBuilder = BattleAIPromptBuilder()

    init(model: SystemLanguageModel = .default) {
        self.model = model
        self.session = LanguageModelSession(instructions: Self.loadInstructions())
    }

    // MARK: - Move picking

    func chooseMove(
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail]
    ) async -> MoveDetail {
        // Belt and braces — caller already ensures non-empty, but if they don't
        // we have no random fallback either, so propagate via a sentinel move.
        guard let firstMove = moves.first else {
            return MoveDetail(name: "tackle")
        }

        guard isAvailable, !session.isResponding else {
            return moves.randomElement() ?? firstMove
        }

        do {
            let prompt = promptBuilder.buildMovePrompt(
                attacker: attacker,
                defender: defender,
                moves: moves
            )
            let choice = try await session.respond(
                generating: MoveChoice.self,
                options: .init(temperature: 0.2, maximumResponseTokens: 32)
            ) { prompt }.content
            return moves.first { $0.name == choice.name } ?? moves.randomElement() ?? firstMove
        } catch {
            return moves.randomElement() ?? firstMove
        }
    }

    // MARK: - Opponent picking

    func chooseOpponent(
        for player: PokemonSummary,
        candidates: [PokemonSummary]
    ) async -> PokemonSummary {
        let filtered = candidates.filter { $0.id != player.id }
        guard let fallback = filtered.randomElement() else {
            // No other pokemon — caller shouldn't allow this but be safe.
            return player
        }

        guard isAvailable, !session.isResponding else { return fallback }

        do {
            let prompt = promptBuilder.buildOpponentPrompt(
                player: player,
                candidates: filtered
            )
            let choice = try await session.respond(
                generating: OpponentChoice.self,
                options: .init(temperature: 0.5, maximumResponseTokens: 16)
            ) { prompt }.content
            return filtered.first { $0.id == choice.id } ?? fallback
        } catch {
            return fallback
        }
    }

    // MARK: - Helpers

    /// True if the on-device language model can actually be invoked on this
    /// device + OS. On older hardware or with Apple Intelligence disabled this
    /// returns false and we skip the model entirely.
    private var isAvailable: Bool {
        if case .available = model.availability { return true }
        return false
    }

    private static func loadInstructions() -> String {
        guard let url = Bundle.main.url(forResource: "BattleAIInstructions", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "You are an expert Pokemon battler. Pick the best move." }
        return text
    }

    // MARK: - Generable outputs

    @Generable(description: "The opponent's chosen move for this turn.")
    struct MoveChoice {
        @Guide(description: "Exact move name in kebab-case from the provided list, e.g. 'thunder-shock'.")
        let name: String
    }

    @Generable(description: "The chosen opponent for the battle.")
    struct OpponentChoice {
        @Guide(description: "Pokedex id (integer) of the chosen opponent from the provided candidate list.")
        let id: Int
    }
}
