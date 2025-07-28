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
            pokemon: viewModel.filteredPokemon,
            grid: .three,
            isLoading: false
        )
        .searchable(text: $viewModel.query)
        .searchFocused($isSearchFocused)
        .onAppear { isSearchFocused = true }
        .overlay(resultText)
        .onChange(of: viewModel.query) { _, _ in
            withAnimation {
                viewModel.filterData()
            }
        }
        .onChange(of: isSearchFocused, dismissSearch)
    }
}

// MARK: - Private functions
private extension SearchView {
    func dismissSearch(_ oldValue: Bool, _ newValue: Bool) {
        guard oldValue == true, newValue == false, viewModel.query.isEmpty else { return }
        selectedTab = .pokedex
    }
}

// MARK: - Private UI components
private extension SearchView {
    var resultText: some View {
        Group {
            if !viewModel.query.isEmpty && viewModel.filteredPokemon.isEmpty {
                Text("No result…")
            } else if viewModel.filteredPokemon.isEmpty {
                Text("Search pokemon and types")
            } else {
                EmptyView()
            }
        }
        .font(.pixel14)
    }
}

#Preview {
    SearchView(viewModel: SearchViewModel(pokemon: []), selectedTab: .constant(.pokedex))
}
