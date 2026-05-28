import SwiftUI
import SwiftData

/// Search tab backed by its own SwiftData `@Query` against the full corpus.
struct SearchView<ViewModel: SearchViewModelProtocol>: View {
    @FocusState private var isSearchFocused: Bool
    @Namespace private var namespace
    @Environment(\.container) private var container
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Pokemon.id) private var corpus: [Pokemon]

    @State var viewModel: ViewModel
    @State private var selectedPokemon: Pokemon?

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.query.isEmpty {
                    emptyState
                } else {
                    PokemonGrid(pokemon: viewModel.filtered) { pokemon in
                        Button {
                            selectedPokemon = pokemon
                        } label: {
                            PokemonSpriteCard(pokemon: pokemon)
                                .applyTransitionSource(id: pokemon.id, namespace: namespace)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .font(.pixel14)
            .searchable(text: $viewModel.query)
            .searchFocused($isSearchFocused)
            .onSubmit(of: .search, viewModel.recordSearch)
            .onAppear {
                viewModel.updateCorpus(corpus)
            }
            .onChange(of: corpus) { _, newCorpus in
                viewModel.updateCorpus(newCorpus)
            }
            .scrollDismissesKeyboard(.immediately)
            .onChange(of: isSearchFocused) { old, new in
                guard old, !new, !viewModel.query.isEmpty else { return }
                viewModel.recordSearch()
            }
            .onChange(of: viewModel.query) { _, _ in
                viewModel.updateFilteredPokemon()
            }
            .sensoryFeedback(.impact(weight: .light), trigger: viewModel.query)
            .applyPokedexStyling(title: Tabs.search.title)
            .navigationDestination(item: $selectedPokemon) { pokemon in
                PokemonDetailView(
                    viewModel: PokemonDetailViewModel(
                        summary: pokemon,
                        container: container,
                        modelContext: modelContext
                    )
                )
                .navigationTransition(.zoom(sourceID: pokemon.id, in: namespace))
            }
        }
    }
}

// MARK: - Private
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
                    container: container,
                    modelContext: modelContext
                )
            )
            .navigationTransition(.zoom(sourceID: pokemon.id, in: namespace))
        }
    }

    var suggestedTermsSection: some View {
        VStack(alignment: .leading, spacing: 8.0) {
            sectionHeader(title: "Try searching for", systemImage: "magnifyingglass")
            FlowLayout(spacing: 6.0) {
                ForEach(ViewModel.suggestedTerms, id: \.self) { term in
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
                Button(action: viewModel.clearRecentSearches) {
                    Image(systemName: "trash.fill")
                        .font(.pixel17)
                        .foregroundStyle(Color.pokedexRed)
                }
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
                        .padding()
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
        LazyVGrid(columns: GridLayout.two.layout, spacing: GridLayout.two.spacing) {
            ForEach(viewModel.suggestedPokemon, id: \.id) { pokemon in
                NavigationLink(value: pokemon) {
                    PokemonSpriteCard(pokemon: pokemon)
                        .matchedTransitionSource(id: pokemon.id, in: namespace)
                }
            }
        }
    }
}

#Preview {
    SearchView(viewModel: SearchViewModel())
}
