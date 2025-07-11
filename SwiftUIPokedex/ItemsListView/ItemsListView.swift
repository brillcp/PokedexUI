import SwiftUI

struct ItemsListView<ViewModel: ItemsListViewModelProtocol>: View {
    @ObservedObject var viewModel: ViewModel

    var body: some View {
        NavigationStack {
            ScrollView {

            }
            .searchable(
                text: $viewModel.query,
                placement: .navigationBarDrawer,
                prompt: Text("Search items…")
            )
            .onChange(of: viewModel.query, viewModel.clearSearch)
            .onSubmit(of: .search, performSearch)
        }
    }
}

// MARK: - Private functions
private extension ItemsListView {
    func performSearch() {
        Task { await viewModel.search() }
    }
}

// MARK: - View Modifiers
private extension View {
    func applyPokedexStyling() -> some View {
        self
            .tint(.pokedexRed)
            .navigationTitle("Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.pokedexRed, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .background(Color.darkGrey)
    }
}

#Preview {
    ItemsListView(viewModel: ItemsListViewModel())
}
