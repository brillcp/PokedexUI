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
            viewModel.updateCorpus(corpus)
        }
        .onChange(of: corpus) { _, newCorpus in
            viewModel.updateCorpus(newCorpus)
        }
        .scrollDismissesKeyboard(.immediately)
        .onChange(of: isSearchFocused) { old, new in
            if old, !new, !viewModel.query.isEmpty {
                viewModel.recordSearch()
            }
        }
        .onChange(of: viewModel.query) { _, _ in
            viewModel.updateFilteredPokemon()
        }
        .sensoryFeedback(.impact(weight: .light), trigger: viewModel.query)
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
                suggestedTermsSection
                if !viewModel.recentSearches.isEmpty {
                    recentSection
                } else {
                    Text("Search Pokemon, types, habitats or abilities")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                        .padding(.top, 80.0)
                        .padding(.horizontal)
                        .lineHeight(.loose)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top)
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

    var suggestedTermsSection: some View {
        VStack(alignment: .leading, spacing: 8.0) {
            sectionHeader(title: "Try searching for", systemImage: "magnifyingglass")
            FlowLayout(spacing: 6.0) {
                ForEach(SearchViewModel.suggestedTerms, id: \.self) { term in
                    Button {
                        viewModel.query = term
                        viewModel.recordSearch()
                    } label: {
                        Chip(term, style: .accent, size: .medium)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal)
    }

    var suggestedSection: some View {
        VStack(alignment: .leading, spacing: 8.0) {
            sectionHeader(title: "Suggested", systemImage: "sparkles.2")
                .padding(.horizontal)
            suggestedGrid
        }
    }

    var recentSection: some View {
        VStack(alignment: .leading, spacing: 8.0) {
            HStack {
                sectionHeader(title: "Recent", systemImage: "clock.arrow.circlepath")
                Spacer()
                Button("Clear", action: viewModel.clearRecentSearches)
                    .font(.pixel12)
                    .foregroundStyle(Color.pokedexRed)
            }
            .padding(.horizontal)
            VStack(spacing: 2.0) {
                ForEach(viewModel.recentSearches, id: \.self) { term in
                    Button {
                        viewModel.query = term
                    } label: {
                        HStack {
                            Label(term, systemImage: "magnifyingglass")
                                .foregroundStyle(.white)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.vertical)
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
}

#Preview {
    SearchView(
        viewModel: SearchViewModel(),
        selectedTab: .constant(.pokedex)
    )
}
