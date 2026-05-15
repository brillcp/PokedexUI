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
/// Inspired by Borealis' `AuroraPredictionService`: same `LanguageModelSession`
/// pattern with instructions loaded from a markdown file and a `@Generable`
/// output struct for structured decoding.
protocol BattleAIServiceProtocol: Sendable {
    /// Pick the opponent's next move given the current battle snapshot.
    /// Falls back to a random move on any failure. `typeChart` is a Sendable
    /// snapshot so the prompt builder can read it off-main without an actor
    /// hop on the hot per-turn path.
    func chooseMove(
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart
    ) async -> MoveDetail

    /// Pick an "interesting" opponent for the player from a candidate roster.
    /// `playerTypes` is fed into the prompt so the model can match against the
    /// player's actual typing instead of guessing from training knowledge.
    /// Falls back to a random non-self opponent on any failure.
    func chooseOpponent(
        for player: PokemonSummary,
        playerTypes: [String],
        candidates: [PokemonSummary]
    ) async -> PokemonSummary

    /// Pick 4 moves for the opponent from its full movepool, knowing who it's
    /// fighting. Symmetric with the player's hand-picked loadout: both sides
    /// commit to 4 moves before the battle starts. AI uses type matchup, base
    /// stats, and move synergy to choose. Falls back to top-4-by-power on any
    /// model failure.
    func chooseLoadout(
        for fighter: BattleCombatant,
        against opponent: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart
    ) async -> [MoveDetail]
}

/// Live `FoundationModels`-backed implementation. Owns one shared
/// `LanguageModelSession` per battle so the model retains conversation
/// memory across turns. Every public call degrades to a deterministic
/// fallback (random pick, top-4-by-power heuristic) if Apple Intelligence
/// isn't available on the device, the session is busy, or decoding fails.
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
        moves: [MoveDetail],
        typeChart: TypeChart
    ) async -> MoveDetail {
        // Belt and braces: caller already ensures non-empty, but if they don't
        // we have no random fallback either, so propagate via a sentinel move.
        guard let firstMove = moves.first else {
            return MoveDetail(name: "tackle")
        }

        guard isAvailable, !session.isResponding else {
            return moves.randomElement() ?? firstMove
        }

        // Pure value lookup with no actor hop. Caller passes a Sendable snapshot.
        let effectiveness = moves.map {
            typeChart.multiplier(attacking: $0.typeName, defenders: defender.typeNames)
        }

        do {
            let prompt = promptBuilder.buildMovePrompt(
                attacker: attacker,
                defender: defender,
                moves: moves,
                effectiveness: effectiveness
            )
            let choice = try await session.respond(
                generating: MoveChoice.self,
                options: .init(temperature: 0.2, maximumResponseTokens: 8)
            ) { prompt }.content
            // Model returns the move's index into the supplied list. Cheaper
            // tokens, no name-typo failures. Clamp to bounds before lookup.
            if (0..<moves.count).contains(choice.index) {
                return moves[choice.index]
            }
            return moves.randomElement() ?? firstMove
        } catch {
            return moves.randomElement() ?? firstMove
        }
    }

    // MARK: - Opponent picking

    func chooseOpponent(
        for player: PokemonSummary,
        playerTypes: [String],
        candidates: [PokemonSummary]
    ) async -> PokemonSummary {
        let filtered = candidates.filter { $0.id != player.id }
        guard let fallback = filtered.randomElement() else {
            // No other pokemon; caller shouldn't allow this but be safe.
            return player
        }

        guard isAvailable, !session.isResponding else { return fallback }

        do {
            let prompt = promptBuilder.buildOpponentPrompt(
                player: player,
                playerTypes: playerTypes,
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

    // MARK: - Loadout picking

    func chooseLoadout(
        for fighter: BattleCombatant,
        against opponent: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart
    ) async -> [MoveDetail] {
        let loadoutSize = 4
        // Deterministic fallback used when the model is unavailable or returns
        // garbage: top-4 by power, tiebreak accuracy, damaging moves first.
        let fallback = Self.heuristicLoadout(from: moves, count: loadoutSize)

        guard moves.count > loadoutSize else { return moves }
        guard isAvailable, !session.isResponding else { return fallback }

        // Pure value lookup, no actor hop.
        let effectiveness = moves.map {
            typeChart.multiplier(attacking: $0.typeName, defenders: opponent.typeNames)
        }

        do {
            let prompt = promptBuilder.buildLoadoutPrompt(
                fighter: fighter,
                opponent: opponent,
                moves: moves,
                effectiveness: effectiveness,
                loadoutSize: loadoutSize
            )
            let choice = try await session.respond(
                generating: LoadoutChoice.self,
                options: .init(temperature: 0.4, maximumResponseTokens: 32)
            ) { prompt }.content
            // Dedupe + clamp; if the model returned fewer than 4 valid indices,
            // pad from the heuristic fallback so the loadout is always full.
            let validIndices = Array(
                Set(choice.indices.filter { (0..<moves.count).contains($0) })
            )
            var picked = validIndices.map { moves[$0] }
            if picked.count < loadoutSize {
                let usedNames = Set(picked.map(\.name))
                for move in fallback where !usedNames.contains(move.name) {
                    picked.append(move)
                    if picked.count == loadoutSize { break }
                }
            }
            return Array(picked.prefix(loadoutSize))
        } catch {
            return fallback
        }
    }

    /// Top-N moves by impact: damaging moves first, then highest power, then
    /// highest accuracy. Used as the fallback when the language model isn't
    /// available or returns invalid output.
    private static func heuristicLoadout(from moves: [MoveDetail], count: Int) -> [MoveDetail] {
        let ranked = moves.sorted { lhs, rhs in
            let lDamaging = (lhs.power ?? 0) > 0
            let rDamaging = (rhs.power ?? 0) > 0
            if lDamaging != rDamaging { return lDamaging }
            let lp = lhs.power ?? 0
            let rp = rhs.power ?? 0
            if lp != rp { return lp > rp }
            return (lhs.accuracy ?? 100) > (rhs.accuracy ?? 100)
        }
        return Array(ranked.prefix(count))
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
        @Guide(description: "Zero-based index of the chosen move in the provided list (e.g. 0 for the first move).")
        let index: Int
    }

    @Generable(description: "The chosen opponent for the battle.")
    struct OpponentChoice {
        @Guide(description: "Pokedex id (integer) of the chosen opponent from the provided candidate list.")
        let id: Int
    }

    @Generable(description: "Four-move loadout picked from the supplied movepool.")
    struct LoadoutChoice {
        @Guide(description: "Exactly 4 zero-based indices into the provided move list. the moves the fighter brings into battle.")
        let indices: [Int]
    }
}
