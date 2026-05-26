import SwiftUI

/// Reusable searchable pokemon grid used by both single-player opponent
/// picker and multiplayer fighter picker. Callers provide the pokemon
/// list and a selection callback. Bottom bars (e.g. AI random) are added
/// by callers via `.safeAreaBar` on top.
///
/// Set `searchable` to false when the caller manages its own search bar
/// (e.g. SearchView). Pass a `namespace` for matched zoom transitions.
struct PokemonPickerGrid: View {
    private static let gridSpacing: CGFloat = 2.0

    let pokemon: [Pokemon]
    var searchEnabled: Bool = true
    var namespace: Namespace.ID?
    let onSelect: (Pokemon) -> Void

    @State private var searchText = ""
    @State private var index: [(pokemon: Pokemon, haystack: String)] = []

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(maximum: .infinity), spacing: Self.gridSpacing), count: 3),
                spacing: Self.gridSpacing
            ) {
                ForEach(displayedPokemon, id: \.id) { pokemon in
                    Button {
                        onSelect(pokemon)
                    } label: {
                        PokemonSpriteCard(pokemon: pokemon)
                            .applyTransitionSource(id: pokemon.id, namespace: namespace)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
        .if(searchEnabled) { view in
            view
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
                .scrollDismissesKeyboard(.immediately)
        }
        .onAppear(perform: buildIndex)
    }
}

// MARK: - Private
private extension PokemonPickerGrid {
    var displayedPokemon: [Pokemon] {
        guard searchEnabled else { return pokemon }
        let terms = searchText
            .split(whereSeparator: \.isWhitespace)
            .map { $0.normalize }
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return pokemon }
        return index.compactMap { entry in
            terms.allSatisfy { entry.haystack.contains($0) } ? entry.pokemon : nil
        }
    }

    func buildIndex() {
        guard searchEnabled, index.isEmpty else { return }
        index = pokemon.map { ($0, Pokemon.searchHaystack(for: $0)) }
    }
}

// MARK: - Helpers
private extension View {
    @ViewBuilder
    func applyTransitionSource(id: Int, namespace: Namespace.ID?) -> some View {
        if let namespace {
            self.matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
