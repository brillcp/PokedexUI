import SwiftUI

/// Items tab showing a paginated list of every PokeAPI item.
struct ItemListView<ViewModel: ItemListViewModelProtocol>: View {
    @State var viewModel: ViewModel

    var body: some View {
        List(viewModel.items, id: \.title) { item in
            itemRow(for: item)
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(Color.cardBackground)
        }
        .font(.pixel14)
        .foregroundStyle(.white)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .overlay {
            if viewModel.isLoading {
                PixelSpinner()
            }
        }
        .task { await viewModel.loadItems() }
    }
}

private extension ItemListView {
    func itemRow(for item: ItemData) -> some View {
        ZStack {
            NavigationLink {
                ItemDetailView(viewModel: ItemDetailViewModel(item: item))
            } label: {
                EmptyView()
            }
            .opacity(0)

            ItemRowView(item: item)
        }
    }
}

#Preview {
    @Previewable
    @Environment(\.modelContext) var modelContext
    ItemListView(viewModel: ItemListViewModel(modelContext: modelContext, container: .live))
}
