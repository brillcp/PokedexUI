import SwiftUI
import SwiftData

struct SearchView<ViewModel: SearchViewModelProtocol>: View {
    @FocusState private var isSearchFocused: Bool
    @Query(sort: \PokemonSummary.id) private var corpus: [PokemonSummary]

    @State var viewModel: ViewModel
    @Binding var selectedTab: Tabs

    var body: some View {
        Group {
            if !viewModel.query.isEmpty && viewModel.filtered.isEmpty {
                Text("No result…")
            } else if viewModel.filtered.isEmpty {
                Text("Search Pokemon and types")
            } else {
                PokedexGridView(pokemon: viewModel.filtered)
            }
        }
        .font(.pixel14)
        .background(Color.darkGrey.ignoresSafeArea())
        .searchable(text: $viewModel.query)
        .searchFocused($isSearchFocused)
        .onAppear { isSearchFocused = true }
        .scrollDismissesKeyboard(.immediately)
        .onChange(of: viewModel.query) { _, _ in
            withAnimation(.bouncy(duration: 0.25)) {
                viewModel.updateFiltered(in: corpus)
            }
        }
        .onChange(of: corpus.count) { _, _ in
            // Pagination just added more summaries, so re-run the current query
            // against the larger corpus so new matches appear without a typing pause.
            viewModel.updateFiltered(in: corpus)
        }
        .onChange(of: isSearchFocused, dismissSearch)
    }
}

private extension SearchView {
    func dismissSearch(_ oldValue: Bool, _ newValue: Bool) {
        guard oldValue, !newValue, viewModel.query.isEmpty else { return }
        withTransaction(.init(animation: .default)) {
            selectedTab = .pokedex
        }
    }
}

#Preview {
    @Previewable @Environment(\.modelContext) var modelContext
    SearchView(
        viewModel: SearchViewModel(),
        selectedTab: .constant(.pokedex)
    )
}
