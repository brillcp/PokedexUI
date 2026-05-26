import SwiftUI
import PokeBattleKit

/// Reusable move selection grid shared by single-player and multiplayer
/// loadout screens. Displays a counter header and a two-column grid of
/// move cards with toggle selection.
struct MovePickerGrid: View {
    let moves: [Move]
    let selectedNames: Set<String>
    let maxSelections: Int
    var opponentTypes: [String] = []
    let onToggle: (Move) -> Void

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
        HStack {
            Text("Pick \(maxSelections) moves")
                .font(.pixel12)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(selectedNames.count)/\(maxSelections)")
                .font(.pixel12)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    var grid: some View {
        LazyVGrid(columns: GridLayout.two.layout, spacing: GridLayout.two.spacing) {
            ForEach(moves, id: \.name) { move in
                moveCard(move)
            }
        }
    }

    func moveCard(_ move: Move) -> some View {
        let selected = selectedNames.contains(move.name)
        let atCap = !selected && selectedNames.count >= maxSelections
        let effectiveness: Double? = opponentTypes.isEmpty
            ? nil
            : PokeBattleKit.typeChart.multiplier(attacking: move.typeName, defenders: opponentTypes)
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                onToggle(move)
            }
        } label: {
            MoveCell(move: move, mode: .loadout(selected: selected), effectiveness: effectiveness)
        }
        .buttonStyle(.plain)
        .opacity(atCap ? Opacity.disabled : 1)
        .disabled(atCap)
    }
}
