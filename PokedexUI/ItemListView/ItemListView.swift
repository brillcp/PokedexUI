import SwiftUI

struct ItemListView<ViewModel: ItemListViewModelProtocol>: View {
    @State var viewModel: ViewModel

    // MARK: - Body
    var body: some View {
        ScrollView(showsIndicators: false) {
            itemList
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
                    .tint(.white)
            }
        }
        .task { await viewModel.loadItems() }
    }
}

// MARK: - View Components
private extension ItemListView {
    var itemList: some View {
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

#Preview {
    ItemListView(viewModel: ItemListViewModel())
}
