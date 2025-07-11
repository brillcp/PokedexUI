import SwiftUI

struct ItemsListView<ViewModel: ItemsListViewModelProtocol>: View {
    @ObservedObject var viewModel: ViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading) {
                    ForEach(viewModel.items, id: \.title) { item in
                        NavigationLink {
                            ItemDetailView(item: item)
                        } label: {
                            HStack {
                                Text(item.title?.pretty ?? "none")
                                Spacer()
                                Text(">")
                            }
                            .padding(.vertical)
                        }
                    }
                }
                .font(.pixel14)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
            }
            .searchable(
                text: $viewModel.query,
                placement: .navigationBarDrawer,
                prompt: Text("Search items…")
            )
            .onChange(of: viewModel.query, viewModel.clearSearch)
            .onSubmit(of: .search, performSearch)
            .applyPokedexStyling(title: "Items")
        }
        .task { await viewModel.loadItems() }
    }
}

// MARK: - Private functions
private extension ItemsListView {
    func performSearch() {
        Task { await viewModel.search() }
    }
}

// MARK: - View Modifiers
extension View {
    func applyPokedexStyling(title: String) -> some View {
        self
            .tint(.pokedexRed)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.pokedexRed, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .background(Color.darkGrey)
    }
}

#Preview {
    ItemsListView(viewModel: ItemsListViewModel())
}
