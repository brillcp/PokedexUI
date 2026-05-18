import SwiftUI
import SwiftData

/// Search tab. Owns its own `@Query` against the SwiftData store so it
/// always reflects the full corpus without prop-drilling from the grid.
struct SearchView: View {
    @FocusState private var isSearchFocused: Bool
    @Namespace private var namespace
    @Environment(\.container) private var container
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
            viewModel.updateFilteredPokemon()
        }
      }
}

// MARK: - Subviews

private extension SearchView {
    @ViewBuilder
    var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24.0) {
                if !viewModel.suggestedPokemon.isEmpty {
                    suggestedSection
                }
                if !viewModel.recentSearches.isEmpty {
                    recentSection
                } else {
                    Text("Search Pokemon, types, habitats or abilities")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                        .padding(.top, 80.0)
                        .lineHeight(.loose)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8.0)
        }
        .scrollIndicators(.hidden)
        .navigationDestination(for: Pokemon.self) { pokemon in
            PokemonDetailView(
                viewModel: PokemonDetailViewModel(
                    summary: pokemon,
                    evolutionService: container.evolutionService
                )
            )
            .navigationTransition(.zoom(sourceID: pokemon.id, in: namespace))
        }
    }

    var suggestedSection: some View {
        VStack(alignment: .leading, spacing: 8.0) {
            sectionHeader(title: "Suggestions", systemImage: "sparkles.2")
                .padding(.horizontal, 16.0)
            suggestedGrid
        }
    }

    var recentSection: some View {
        VStack(alignment: .leading, spacing: 8.0) {
            HStack {
                sectionHeader(title: "Recent Searches", systemImage: "clock.arrow.circlepath")
                Spacer()
                Button("Clear", action: viewModel.clearRecentSearches)
                    .font(.pixel12)
                    .foregroundStyle(Color.pokedexRed ?? .red)
            }
            .padding(.horizontal, 16.0)
            VStack(spacing: 1.0) {
                ForEach(viewModel.recentSearches, id: \.self) { term in
                    Button {
                        viewModel.query = term
                    } label: {
                        HStack {
                            Label(term, systemImage: "magnifyingglass")
                                .foregroundStyle(.white)
                            Spacer()
                        }
                        .padding(.horizontal, 16.0)
                        .padding(.vertical, 12.0)
                        .frame(maxWidth: .infinity)
                        .background(Color.cardBackground)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    func sectionHeader(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.pixel12)
            .foregroundStyle(.secondary)
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
                NavigationLink(value: pokemon) {
                    PokemonSpriteCard(
                        id: pokemon.id,
                        name: pokemon.name.capitalized,
                        spriteURL: pokemon.frontSprite
                    )
                    .matchedTransitionSource(id: pokemon.id, in: namespace)
                    .tint(.white)
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
