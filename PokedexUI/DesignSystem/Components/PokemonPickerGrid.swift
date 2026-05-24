import SwiftUI

/// Reusable searchable pokemon grid used by both single-player opponent
/// picker and multiplayer fighter picker. Callers provide the pokemon
/// list and a selection callback. Bottom bars (e.g. AI random) are added
/// by callers via `.safeAreaBar` on top.
struct PokemonPickerGrid: View {
    let pokemon: [Pokemon]
    let onSelect: (Pokemon) -> Void

    @State private var searchText = ""

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(maximum: .infinity), spacing: 2),
                    GridItem(.flexible(maximum: .infinity), spacing: 2),
                    GridItem(.flexible(maximum: .infinity), spacing: 2)
                ],
                spacing: 2
            ) {
                ForEach(filteredPokemon, id: \.id) { pokemon in
                    Button {
                        onSelect(pokemon)
                    } label: {
                        PokemonSpriteCard(pokemon: pokemon)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
    }
}

// MARK: - Private
private extension PokemonPickerGrid {
    var filteredPokemon: [Pokemon] {
        guard !searchText.isEmpty else { return pokemon }
        let query = searchText.lowercased()
        return pokemon.filter { $0.name.lowercased().contains(query) }
    }
}
