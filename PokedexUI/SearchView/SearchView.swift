import SwiftUI

struct SearchView<ViewModel: SearchViewModelProtocol>: View {
    // MARK: Private properties
    @FocusState private var isSearchFocused: Bool
    @Binding private var viewModel: ViewModel

    // MARK: - Init
    init(viewModel: ViewModel) {
        self._viewModel = .constant(viewModel)
    }

    // MARK: - Body
    var body: some View {
        PokedexGridView(
            pokemon: viewModel.filteredPokemon,
            grid: .three,
            isLoading: false
        )
        .focused($isSearchFocused)
        .searchable(text: $viewModel.query)
        .onAppear { isSearchFocused = true }
        .overlay(resultText)
        .onChange(of: viewModel.query) { _, _ in
            withAnimation {
                viewModel.filterData()
            }
        }
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
    SearchView(viewModel: SearchViewModel(pokemon: []))
}
