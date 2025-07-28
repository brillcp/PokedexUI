import SwiftUI

struct ItemsListView<ViewModel: ItemsListViewModelProtocol>: View {
    @State var viewModel: ViewModel

    // MARK: - Body
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

#Preview {
    ItemsListView(viewModel: ItemsListViewModel())
}
