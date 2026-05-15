import Foundation

/// Payload handed from `BattleSetupView` (sheet) back to the parent detail
/// view, which then pushes `BattleView`. Carries the fully-hydrated combatants
/// and the chosen movesets so the battle screen never re-runs preflight.
///
/// `Identifiable` via a fresh UUID per launch so SwiftUI's
/// `navigationDestination(item:)` treats every rematch as a distinct push.
struct BattleLaunch: Identifiable, Hashable {
    let id = UUID()
    let player: PokemonViewModel
    let opponent: PokemonViewModel
    let playerMoves: [MoveDetail]
    let opponentMoves: [MoveDetail]

    static func == (lhs: BattleLaunch, rhs: BattleLaunch) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
