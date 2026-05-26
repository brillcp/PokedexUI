import SwiftUI

/// Pure display grid of Pokemon sprite cards.
/// Callers pass pre-filtered data and an optional namespace for zoom transitions.
struct PokemonGrid: View {
    private static let gridSpacing: CGFloat = 2.0

    let pokemon: [Pokemon]
    var namespace: Namespace.ID?
    let onSelect: (Pokemon) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(maximum: .infinity), spacing: Self.gridSpacing), count: 3),
                spacing: Self.gridSpacing
            ) {
                ForEach(pokemon, id: \.id) { pokemon in
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
    }
}

/// Searchable Pokemon grid used by opponent picker, multiplayer fighter picker,
/// and bookmarks. Wraps `PokemonGrid` with a toolbar search bar and
/// haystack-based filtering.
///
/// Callers that manage their own search (e.g. SearchView) should use
/// `PokemonGrid` directly instead.
struct PokemonPickerGrid: View {
    let pokemon: [Pokemon]
    var namespace: Namespace.ID?
    let onSelect: (Pokemon) -> Void

    @State private var searchText = ""
    @State private var index: [(pokemon: Pokemon, haystack: String)] = []

    var body: some View {
        PokemonGrid(pokemon: displayedPokemon, namespace: namespace, onSelect: onSelect)
            .searchable(text: $searchText, placement: .toolbar)
            .scrollDismissesKeyboard(.immediately)
            .onAppear(perform: buildIndex)
    }
}

// MARK: - Private
private extension PokemonPickerGrid {
    var displayedPokemon: [Pokemon] {
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
        guard index.isEmpty else { return }
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
}
