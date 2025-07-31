import SwiftUI

struct ItemDetailView<ViewModel: ItemDetailViewModelProtocol>: View {
    let viewModel: ViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading) {
                ForEach(viewModel.items, id: \.id) { item in
                    ItemDetailRowView(item: item)
                    Divider().background(.secondary)
                }
            }
            .font(.pixel14)
            .foregroundStyle(.white)
            .padding()
        }
        .applyPokedexStyling(title: viewModel.title)
    }
}

#Preview {
    ItemDetailView(viewModel: ItemDetailViewModel(item: .init(title: "title", items: [])))
}
