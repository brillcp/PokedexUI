import Foundation

/// Payload handed from `BattleSetupView` (sheet) back to the parent detail
/// view, which then pushes `BattleView`. Carries a pre-built
/// `BattleViewModel` so the navigation push doesn't pay the combatant +
/// engine construction cost mid-transition; everything heavy runs at
/// "Start" tap time instead.
///
/// `Identifiable` via a fresh UUID per launch so SwiftUI's
/// `navigationDestination(item:)` treats every rematch as a distinct push.
struct BattleLaunch: Identifiable, Hashable {
    let id = UUID()
    let viewModel: BattleViewModel

    static func == (lhs: BattleLaunch, rhs: BattleLaunch) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
