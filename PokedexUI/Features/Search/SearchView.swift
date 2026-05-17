import SwiftUI
import SwiftData

/// Search tab. Owns its own `@Query` against the SwiftData store so it
/// always reflects the full corpus without prop-drilling from the grid.
struct SearchView: View {
    @FocusState private var isSearchFocused: Bool
    @Query(sort: \Pokemon.id) private var corpus: [Pokemon]

    @State var viewModel: SearchViewModel
    @Binding var selectedTab: Tabs

    var body: some View {
        Group {
            if viewModel.query.isEmpty {
                emptyState
            } else {
                PokedexGridView(pokemon: viewModel.filtered)
            }
        }
        .font(.pixel14)
        .background(Color.darkGrey.ignoresSafeArea())
        .searchable(text: $viewModel.query)
        .searchFocused($isSearchFocused)
        .onSubmit(of: .search) { viewModel.recordSearch() }
        .onAppear {
            isSearchFocused = true
            viewModel.updateCorpus(corpus)
        }
        .onChange(of: corpus) { _, newCorpus in
            viewModel.updateCorpus(newCorpus)
        }
        .scrollDismissesKeyboard(.immediately)
        .onChange(of: viewModel.query) { _, _ in
            withAnimation(.bouncy(duration: 0.25)) {
                viewModel.updateFilteredPokemon()
            }
        }
//        .onChange(of: isSearchFocused, dismissSearch)
    }
}

// MARK: - Subviews

private extension SearchView {
    @ViewBuilder
    var emptyState: some View {
        List {
            if !viewModel.suggestedPokemon.isEmpty {
                Section("Suggested Pokemon") {
                    suggestedGrid
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            if !viewModel.recentSearches.isEmpty {
                Section {
                    ForEach(viewModel.recentSearches, id: \.self) { term in
                        Button {
                            viewModel.query = term
                        } label: {
                            Label(term, systemImage: "clock.arrow.circlepath")
                                .foregroundStyle(.white)
                        }
                        .listRowBackground(Color.cardBackground)
                    }
                } header: {
                    HStack {
                        Label("Recent Searches", systemImage: "clock.arrow.circlepath")
                        Spacer()
                        Button("Clear", action: viewModel.clearRecentSearches)
                            .font(.pixel12)
                            .foregroundStyle(Color.pokedexRed ?? .red)
                            .textCase(nil)
                    }
                }
            } else {
                Text("Search Pokemon and types")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    var suggestedGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(maximum: .infinity), spacing: 2.0),
                GridItem(.flexible(maximum: .infinity), spacing: 2.0)
            ],
            spacing: 2.0
        ) {
            ForEach(viewModel.suggestedPokemon, id: \.id) { pokemon in
                NavigationLink {
                    PokemonDetailView(viewModel: PokemonDetailViewModel(summary: pokemon))
                } label: {
                    PokemonSpriteCard(
                        id: pokemon.id,
                        name: pokemon.name.capitalized,
                        spriteURL: pokemon.frontSprite
                    )
                }
            }
        }
    }

    func dismissSearch(_ oldValue: Bool, _ newValue: Bool) {
        guard oldValue, !newValue, viewModel.query.isEmpty else { return }
        withTransaction(.init(animation: .default)) {
            selectedTab = .pokedex
        }
    }
}

#Preview {
    SearchView(
        viewModel: SearchViewModel(),
        selectedTab: .constant(.pokedex)
    )
}
