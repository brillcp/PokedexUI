import SwiftUI

struct SearchView<ViewModel: SearchViewModelProtocol>: View {
    // MARK: Private properties
    @FocusState private var isSearchFocused: Bool

    // MARK: - Public properties
    @State var viewModel: ViewModel
    @Binding var selectedTab: Tabs

    // MARK: - Body
    var body: some View {
        PokedexGridView(
            pokemon: viewModel.filtered,
            grid: .three
        )
        .searchable(text: $viewModel.query)
        .searchFocused($isSearchFocused)
        .onAppear { isSearchFocused = true }
        .overlay(resultText)
        .scrollDismissesKeyboard(.immediately)
        .onChange(of: viewModel.query) { _, _ in
            withAnimation(.bouncy) { viewModel.updateFilteredPokemon() }
        }
        .onChange(of: isSearchFocused, dismissSearch)
    }
}

// MARK: - Private functions
private extension SearchView {
    func dismissSearch(_ oldValue: Bool, _ newValue: Bool) {
        guard oldValue, !newValue, viewModel.query.isEmpty else { return }
        withTransaction(.init(animation: .default)) {
            selectedTab = .pokedex
        }
    }
}

// MARK: - Private UI components
private extension SearchView {
    var resultText: some View {
        Group {
            if !viewModel.query.isEmpty && viewModel.filtered.isEmpty {
                Text("No result…")
            } else if viewModel.filtered.isEmpty {
                Text("Search Pokemon and types")
            } else {
                EmptyView()
            }
        }
        .font(.pixel14)
    }
}

#Preview {
    @Previewable
    @Environment(\.modelContext) var modelContext
    SearchView(
        viewModel: SearchViewModel(pokemon: [.init(pokemon: .pikachu)]),
        selectedTab: .constant(.pokedex)
    )
}
