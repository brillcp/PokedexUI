import SwiftUI

struct ItemsListView<ViewModel: ItemsListViewModelProtocol>: View {
    @ObservedObject var viewModel: ViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            itemsList
        }
        .searchable(
            text: $viewModel.query,
            placement: .navigationBarDrawer,
            prompt: Text("Search items…")
        )
        .onChange(of: viewModel.query, viewModel.clearSearch)
        .onSubmit(of: .search, performSearch)
        .task { await viewModel.loadItems() }
    }
}

// MARK: - View Components
private extension ItemsListView {
    var itemsList: some View {
        LazyVStack(alignment: .leading) {
            ForEach(viewModel.items, id: \.title) { item in
                itemRow(for: item)
            }
        }
        .font(.pixel14)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
    }

    func itemRow(for item: ItemData) -> some View {
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

// MARK: - Actions
private extension ItemsListView {
    func performSearch() {
        Task { await viewModel.search() }
    }
}

#Preview {
    ItemsListView(viewModel: ItemsListViewModel())
}
