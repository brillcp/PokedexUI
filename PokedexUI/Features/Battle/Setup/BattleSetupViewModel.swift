import Foundation
import SwiftData
import SwiftUI

/// Pre-battle loadout preparation protocol.
@MainActor
protocol BattleSetupViewModelProtocol {
    /// Raw player pokemon passed in from the picker.
    var playerSummary:   Pokemon { get }
    /// Raw opponent pokemon chosen by AI or user.
    var opponentSummary: Pokemon { get }
    /// Hydrated player view model, populated by `prepare`.
    var playerPokemon:   PokemonViewModel? { get }
    /// Hydrated opponent view model, populated by `prepare`.
    var opponentPokemon: PokemonViewModel? { get }
    /// Player's selectable move pool, ranked by combat impact.
    var playerMovePool:  [MoveDetail] { get }
    /// AI-chosen opponent loadout; `nil` until the AI task resolves.
    var opponentLoadout: [MoveDetail]? { get }
    /// Names of moves the player has currently selected.
    var selectedMoveNames: Set<String> { get }
    /// True once both sides, the player move pool, and the type chart are loaded.
    var isReady: Bool { get }
    /// Maximum number of moves the player may pick.
    var maxSelections: Int { get }
    /// User-facing error surfaced by `prepare` failures.
    var errorMessage: String? { get }

    /// Hydrate both sides, fetch move pools, kick off AI loadout.
    func prepare(modelContext: ModelContext) async
    /// Toggle a move selection, capped at `maxSelections`.
    func toggle(_ move: MoveDetail)
    /// True when player has picked enough moves and AI loadout is ready.
    var canStart: Bool { get }
    /// Player's chosen moves in selection order.
    func playerMoves() -> [MoveDetail]
}

/// Concrete implementation of `BattleSetupViewModelProtocol`.
@MainActor
@Observable
final class BattleSetupViewModel {
    private var selectionOrder:  [String] = []
    private let movePrefetcher:  MovePrefetching
    private let aiService:       BattleAIServiceProtocol
    private let typeChartLoader: TypeChartLoader

    let playerSummary:   Pokemon
    let opponentSummary: Pokemon
    let maxSelections:   Int = 4

    var playerPokemon:    PokemonViewModel?
    var opponentPokemon:  PokemonViewModel?
    var playerMovePool:   [MoveDetail] = []
    var opponentLoadout:  [MoveDetail]?
    var selectedMoveNames: Set<String> = []
    var errorMessage: String?

    init(
        player: Pokemon,
        opponent: Pokemon,
        movePrefetcher: MovePrefetching,
        aiService: BattleAIServiceProtocol,
        typeChart: TypeChartLoader
    ) {
        self.playerSummary  = player
        self.opponentSummary = opponent
        self.movePrefetcher = movePrefetcher
        self.aiService      = aiService
        self.typeChartLoader = typeChart
    }
}

// MARK: - BattleSetupViewModelProtocol

extension BattleSetupViewModel: BattleSetupViewModelProtocol {
    var isReady: Bool {
        playerPokemon != nil
            && opponentPokemon != nil
            && !playerMovePool.isEmpty
            && typeChartLoader.chart != nil
    }

    var canStart: Bool {
        selectedMoveNames.count == maxSelections && opponentLoadout != nil
    }

    func toggle(_ move: MoveDetail) {
        if selectedMoveNames.contains(move.name) {
            selectedMoveNames.remove(move.name)
            selectionOrder.removeAll { $0 == move.name }
            return
        }
        guard selectedMoveNames.count < maxSelections else { return }
        selectedMoveNames.insert(move.name)
        selectionOrder.append(move.name)
    }

    func playerMoves() -> [MoveDetail] {
        let byName = Dictionary(uniqueKeysWithValues: playerMovePool.map { ($0.name, $0) })
        return selectionOrder.compactMap { byName[$0] }
    }

    func prepare(modelContext: ModelContext) async {
        let player   = PokemonViewModel(pokemon: playerSummary)
        let opponent = PokemonViewModel(pokemon: opponentSummary)
        self.playerPokemon   = player
        self.opponentPokemon = opponent

        await movePrefetcher.warmUp(modelContainer: modelContext.container)

        let playerMoves  = fetchMoves(for: player,   modelContext: modelContext)
        let opponentPool = fetchMoves(for: opponent, modelContext: modelContext)

        guard playerMoves.count >= maxSelections else {
            errorMessage = "Couldn't load \(playerSummary.name)'s movepool. Check your connection and try again."
            return
        }
        guard opponentPool.count >= maxSelections else {
            errorMessage = "Couldn't load \(opponentSummary.name)'s movepool. Check your connection and try again."
            return
        }

        await typeChartLoader.loadIfNeeded()
        guard let chart = typeChartLoader.chart else {
            errorMessage = "Couldn't load the type chart. Check your connection and try again."
            return
        }

        self.playerMovePool = Self.rankedByImpact(playerMoves)

        let fighter = BattleCombatant(pokemon: opponent, moves: [])
        let foe     = BattleCombatant(pokemon: player,   moves: [])
        let selectionTarget = maxSelections
        Task { [aiService, opponentPool, chart, fighter, foe] in
            let picks = await aiService.chooseLoadout(
                for: fighter,
                against: foe,
                moves: opponentPool,
                typeChart: chart
            )
            await MainActor.run {
                guard picks.count >= selectionTarget else {
                    self.errorMessage = "Opponent couldn't pick a loadout."
                    return
                }
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.opponentLoadout = picks
                }
            }
        }
    }
}

private extension BattleSetupViewModel {
    static func rankedByImpact(_ moves: [MoveDetail]) -> [MoveDetail] {
        moves.sorted { lhs, rhs in
            let lDamage = (lhs.power ?? 0) > 0
            let rDamage = (rhs.power ?? 0) > 0
            if lDamage != rDamage { return lDamage }
            let lp = lhs.power ?? 0
            let rp = rhs.power ?? 0
            if lp != rp { return lp > rp }
            return (lhs.accuracy ?? 100) > (rhs.accuracy ?? 100)
        }
    }

    func fetchMoves(for pokemon: PokemonViewModel, modelContext: ModelContext) -> [MoveDetail] {
        let names = pokemon.pokemon.moves.map(\.move.name)
        guard !names.isEmpty else { return [] }
        let capped = Set(names)
        let descriptor = FetchDescriptor<MoveDetail>(
            predicate: #Predicate { capped.contains($0.name) }
        )
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return all.filter(\.isBattleReady)
    }
}
