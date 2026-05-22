import Foundation
import SwiftData
import SwiftUI
import PokeBattleKit

/// Discrete states the setup screen moves through.
enum BattleSetupPhase: Equatable {
    case loading
    case picking
    case awaitingAI
    case readyToRequest
    case readyToStart
}

/// Pre-battle loadout preparation protocol.
@MainActor
protocol BattleSetupViewModelProtocol {
    var playerSummary:   Pokemon { get }
    var opponentSummary: Pokemon { get }
    var playerPokemon:   PokemonViewModel? { get }
    var opponentPokemon: PokemonViewModel? { get }
    var playerMovePool:  [Move] { get }
    var opponentLoadout: [Move]? { get }
    var selectedMoveNames: Set<String> { get }
    var maxSelections: Int { get }
    var errorMessage: String? { get }
    var phase: BattleSetupPhase { get }

    func prepare() async
    func toggle(_ move: Move)
    func requestOpponentLoadout() async
    func playerMoves() -> [Move]
}

/// Concrete implementation of `BattleSetupViewModelProtocol`.
@MainActor
@Observable
final class BattleSetupViewModel {
    private var selectionOrder:  [String] = []
    private var opponentPool:    [Move] = []
    private let aiService:       BattleAIServiceProtocol

    let playerSummary:   Pokemon
    let opponentSummary: Pokemon
    let maxSelections:   Int = 4

    var playerPokemon:    PokemonViewModel?
    var opponentPokemon:  PokemonViewModel?
    var playerMovePool:   [Move] = []
    var opponentLoadout:  [Move]?
    var selectedMoveNames: Set<String> = []
    var errorMessage: String?
    private(set) var isPickingLoadout: Bool = false

    init(
        player: Pokemon,
        opponent: Pokemon,
        aiService: BattleAIServiceProtocol
    ) {
        self.playerSummary   = player
        self.opponentSummary = opponent
        self.aiService       = aiService
    }
}

// MARK: - BattleSetupViewModelProtocol

extension BattleSetupViewModel: BattleSetupViewModelProtocol {
    var phase: BattleSetupPhase {
        guard playerPokemon != nil,
              opponentPokemon != nil,
              !playerMovePool.isEmpty
        else { return .loading }
        guard selectedMoveNames.count == maxSelections else { return .picking }
        if isPickingLoadout { return .awaitingAI }
        if opponentLoadout != nil { return .readyToStart }
        return .readyToRequest
    }

    func toggle(_ move: Move) {
        if selectedMoveNames.contains(move.name) {
            selectedMoveNames.remove(move.name)
            selectionOrder.removeAll { $0 == move.name }
            return
        }
        guard selectedMoveNames.count < maxSelections else { return }
        selectedMoveNames.insert(move.name)
        selectionOrder.append(move.name)
    }

    func playerMoves() -> [Move] {
        let byName = Dictionary(uniqueKeysWithValues: playerMovePool.map { ($0.name, $0) })
        return selectionOrder.compactMap { byName[$0] }
    }

    func prepare() async {
        let player   = PokemonViewModel(pokemon: playerSummary)
        let opponent = PokemonViewModel(pokemon: opponentSummary)
        self.playerPokemon   = player
        self.opponentPokemon = opponent

        let playerMoves   = movesForPokemon(player)
        let opponentMoves = movesForPokemon(opponent)

        guard playerMoves.count >= maxSelections else {
            errorMessage = "Couldn't load \(playerSummary.name)'s movepool. Check your connection and try again."
            return
        }
        guard opponentMoves.count >= maxSelections else {
            errorMessage = "Couldn't load \(opponentSummary.name)'s movepool. Check your connection and try again."
            return
        }

        self.playerMovePool = Self.rankedByImpact(playerMoves)
        self.opponentPool   = opponentMoves
    }

    func requestOpponentLoadout() async {
        guard let player = playerPokemon,
              let opponent = opponentPokemon else { return }

        isPickingLoadout = true
        let chart   = PokeBattleKit.typeChart
        let fighter = Combatant(pokemon: opponent, moves: [])
        let foe     = Combatant(pokemon: player,  moves: [])
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
    static func rankedByImpact(_ moves: [Move]) -> [Move] {
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

    func movesForPokemon(_ pokemon: PokemonViewModel) -> [Move] {
        let names = Set(pokemon.pokemon.moveNames)
        return PokeBattleKit.allMoves.filter { names.contains($0.name) && $0.isBattleReady }
    }
}
