import SwiftUI
import PokeBattleKit

/// Reusable move selection grid shared by single-player and multiplayer
/// loadout screens. Displays a counter header and a two-column grid of
/// move cards with toggle selection.
struct MovePickerGrid: View {
    let moveSelection: MoveSelection
    var opponentTypes: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            grid
        }
    }
}

// MARK: - Private
private extension MovePickerGrid {
    var header: some View {
        Text("\(moveSelection.selectedNames.count)/\(moveSelection.maxSelections)")
            .font(.pixel12)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
    }

    var grid: some View {
        LazyVGrid(columns: GridLayout.two.layout, spacing: GridLayout.two.spacing) {
            ForEach(moveSelection.pool, id: \.name, content: moveCard)
        }
    }

    func moveCard(_ move: Move) -> some View {
        let selected = moveSelection.selectedNames.contains(move.name)
        let atCap = !selected && moveSelection.selectedNames.count >= moveSelection.maxSelections
        let effectiveness: Double? = opponentTypes.isEmpty
            ? nil
            : PokeBattleKit.typeChart.multiplier(attacking: move.typeName, defenders: opponentTypes)
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                moveSelection.toggle(move)
            }
        } label: {
            MoveCell(move: move, mode: .loadout(selected: selected), effectiveness: effectiveness)
        }
        .buttonStyle(.plain)
        .opacity(atCap ? Opacity.disabled : 1)
        .disabled(atCap)
        .sensoryFeedback(.impact(weight: .light), trigger: selected)
    }
}
