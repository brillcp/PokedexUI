import SwiftUI

struct ItemsListView<ViewModel: ItemsListViewModelProtocol & Sendable>: View {
    @ObservedObject var viewModel: ViewModel

    init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            itemsList
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
                    .tint(.white)
            }
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
        .padding(.horizontal)
    }

    func itemRow(for item: ItemData) -> some View {
        NavigationLink {
            ItemDetailView(viewModel: ItemDetailViewModel(item: item))
        } label: {
            ItemRowView(item: item)
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
