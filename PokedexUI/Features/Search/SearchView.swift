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
                sectionHeader(title: "Recent Searches", systemImage: "clock.arrow.circlepath")
                Spacer()
                Button("Clear", action: viewModel.clearRecentSearches)
                    .font(.pixel12)
                    .foregroundStyle(Color.pokedexRed ?? .red)
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

// MARK: - FlowLayout

/// Wrapping horizontal layout where each child hugs its content width.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let height = rows.reduce(CGFloat.zero) { total, row in
            total + row.height + (total > 0 ? spacing : 0)
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        var index = 0
        for row in rows {
            var x = bounds.minX
            for _ in 0..<row.count {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += size.width + spacing
                index += 1
            }
            y += row.height + spacing
        }
    }
}

private extension FlowLayout {
    struct Row {
        var count: Int
        var height: CGFloat
    }

    func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var currentRow = Row(count: 0, height: 0)
        var x: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && currentRow.count > 0 {
                rows.append(currentRow)
                currentRow = Row(count: 0, height: 0)
                x = 0
            }
            currentRow.count += 1
            currentRow.height = max(currentRow.height, size.height)
            x += size.width + spacing
        }
        if currentRow.count > 0 {
            rows.append(currentRow)
        }
        return rows
    }
}

#Preview {
    SearchView(
        viewModel: SearchViewModel(),
        selectedTab: .constant(.pokedex)
    )
}
