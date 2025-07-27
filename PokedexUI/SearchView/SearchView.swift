import SwiftUI

struct SearchView<ViewModel: SearchViewModelProtocol>: View {
    // MARK: Private properties
    @FocusState private var isSearchFocused: Bool
    @State private var grid: GridLayout = .three
    @Binding private var viewModel: ViewModel
    @Namespace private var namespace

    // MARK: - Init
    init(viewModel: ViewModel) {
        self._viewModel = .constant(viewModel)
    }

    // MARK: - Body
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: grid.layout) {
                ForEach(viewModel.filteredPokemon, id: \.id) { pokemon in
                    NavigationLink {
                        PokemonDetailView(viewModel: pokemon)
                            .navigationTransition(
                                .zoom(sourceID: pokemon.id, in: namespace)
                            )
                    } label: {
                        AsyncImageView(
                            viewModel: pokemon,
                            showOverlay: grid == .three
                        )
                        .matchedTransitionSource(id: pokemon.id, in: namespace)
                        .font(.pixel12)
                    }
                    .padding(8)
                }
            }
            .padding(8)
        }
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
