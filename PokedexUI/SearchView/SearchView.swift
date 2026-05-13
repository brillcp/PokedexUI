import SwiftUI

struct SearchView<ViewModel: SearchViewModelProtocol>: View {
    // MARK: Private properties
    @FocusState private var isSearchFocused: Bool

    // MARK: - Public properties
    @State var viewModel: ViewModel
    @Binding var selectedTab: Tabs

    // MARK: - Body
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
            withAnimation(.bouncy(duration: 0.25)) { viewModel.updateFilteredPokemon() }
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

#Preview {
    @Previewable
    @Environment(\.modelContext) var modelContext
    SearchView(
        viewModel: SearchViewModel(pokemon: [.init(pokemon: .pikachu)]),
        selectedTab: .constant(.pokedex)
    )
}
