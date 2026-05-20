import Foundation

/// Payload for navigating from setup to battle, carrying a pre-built view model.
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
