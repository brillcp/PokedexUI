import SwiftUI

/// Reusable searchable pokemon grid used by both single-player opponent
/// picker and multiplayer fighter picker. Callers provide the pokemon
/// list and a selection callback. Bottom bars (e.g. AI random) are added
/// by callers via `.safeAreaBar` on top.
struct PokemonPickerGrid: View {
    let pokemon: [Pokemon]
    let onSelect: (Pokemon) -> Void

    @State private var searchText = ""
    @State private var index: [(pokemon: Pokemon, haystack: String)] = []

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
        .onAppear(perform: buildIndex)
    }
}

// MARK: - Private
private extension PokemonPickerGrid {
    func buildIndex() {
        guard index.isEmpty else { return }
        index = pokemon.map { ($0, Pokemon.searchHaystack(for: $0)) }
    }

    var filteredPokemon: [Pokemon] {
        let terms = searchText
            .split(whereSeparator: \.isWhitespace)
            .map { $0.normalize }
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return pokemon }
        return index.compactMap { entry in
            terms.allSatisfy { entry.haystack.contains($0) } ? entry.pokemon : nil
        }
    }
}
