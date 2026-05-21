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
    /// True while AI is choosing its loadout after the player locks in.
    var isPickingLoadout: Bool { get }

    /// Hydrate both sides, fetch move pools.
    func prepare(modelContext: ModelContext) async
    /// Toggle a move selection, capped at `maxSelections`.
    func toggle(_ move: MoveDetail)
    /// True when player has picked enough moves to request AI loadout.
    var canRequestLoadout: Bool { get }
    /// True when both sides have their loadouts locked in.
    var canStart: Bool { get }
    /// Ask AI to pick loadout based on what the player chose.
    func requestOpponentLoadout() async
    /// Player's chosen moves in selection order.
    func playerMoves() -> [MoveDetail]
}

/// Concrete implementation of `BattleSetupViewModelProtocol`.
@MainActor
@Observable
final class BattleSetupViewModel {
    private var selectionOrder:  [String] = []
    private var opponentPool:    [MoveDetail] = []
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
    var isPickingLoadout: Bool = false

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

    var canRequestLoadout: Bool {
        selectedMoveNames.count == maxSelections && opponentLoadout == nil && !isPickingLoadout
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

        let playerMoves   = fetchMoves(for: player,   modelContext: modelContext)
        let opponentMoves = fetchMoves(for: opponent, modelContext: modelContext)

        guard playerMoves.count >= maxSelections else {
            errorMessage = "Couldn't load \(playerSummary.name)'s movepool. Check your connection and try again."
            return
        }
        guard opponentMoves.count >= maxSelections else {
            errorMessage = "Couldn't load \(opponentSummary.name)'s movepool. Check your connection and try again."
            return
        }

        await typeChartLoader.loadIfNeeded()
        guard typeChartLoader.chart != nil else {
            errorMessage = "Couldn't load the type chart. Check your connection and try again."
            return
        }

        self.playerMovePool = Self.rankedByImpact(playerMoves)
        self.opponentPool   = opponentMoves
    }

    func requestOpponentLoadout() async {
        guard let player = playerPokemon,
              let opponent = opponentPokemon,
              let chart = typeChartLoader.chart else { return }

        isPickingLoadout = true
        let fighter = BattleCombatant(pokemon: opponent, moves: [])
        let foe     = BattleCombatant(pokemon: player,  moves: [])
        let chosen  = playerMoves()

        let picks = await aiService.chooseLoadout(
            for: fighter,
            against: foe,
            moves: opponentPool,
            playerMoves: chosen,
            typeChart: chart
        )

        guard picks.count >= maxSelections else {
            errorMessage = "Opponent couldn't pick a loadout."
            isPickingLoadout = false
            return
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            self.opponentLoadout = picks
        }
        isPickingLoadout = false
    }
}

// MARK: - Private
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
