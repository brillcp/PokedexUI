import SwiftUI

struct ItemDetailView<ViewModel: ItemDetailViewModelProtocol>: View {
    let viewModel: ViewModel

    var body: some View {
        List(viewModel.items, id: \.id) { item in
            ItemDetailRowView(item: item)
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(Color(.systemGray4))
        }
        .font(.pixel14)
        .foregroundStyle(.white)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .applyPokedexStyling(title: viewModel.title)
    }
}

#Preview {
    ItemDetailView(viewModel: ItemDetailViewModel(item: .init(title: "title", items: [])))
}
