import SwiftUI
import PokeBattleKit

/// Reusable loadout screen showing a pokemon summary card, a move picker
/// grid, and a caller-provided bottom bar button. Used by both
/// single-player and multiplayer loadout flows.
struct MoveLoadoutView<BottomBar: View>: View {
    let pokemon: Pokemon
    let moves: [Move]
    let selectedNames: Set<String>
    let maxSelections: Int
    var opponentTypes: [String] = []
    var isDisabled: Bool = false
    let onToggle: (Move) -> Void
    @ViewBuilder let bottomBar: () -> BottomBar

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                pokemonSummary
                MovePickerGrid(
                    moves: moves,
                    selectedNames: selectedNames,
                    maxSelections: maxSelections,
                    opponentTypes: opponentTypes,
                    onToggle: onToggle
                )
            }
        }
        .scrollIndicators(.hidden)
        .disabled(isDisabled)
        .opacity(isDisabled ? Opacity.disabled : 1)
        .animation(.easeInOut(duration: 0.2), value: isDisabled)
        .safeAreaBar(edge: .bottom, content: bottomBar)
    }
}

// MARK: - Private
private extension MoveLoadoutView {
    var pokemonSummary: some View {
        HStack(spacing: 12) {
            SpriteImage(url: pokemon.frontSprite)
                .frame(width: 80, height: 80)
            VStack(alignment: .leading, spacing: 4) {
                Text(pokemon.name)
                    .font(.pixel14)
                HStack(spacing: 4) {
                    ForEach(pokemon.types) { type in
                        Chip(
                            type.type.name.uppercased(),
                            style: .custom(background: TypeColor.color(for: type.type.name))
                        )
                    }
                }
            }
            Spacer()
        }
        .padding()
        .background(Color.cardBackground)
    }
}
