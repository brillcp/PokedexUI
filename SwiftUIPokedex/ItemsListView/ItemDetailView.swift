import SwiftUI

struct ItemDetailView: View {
    let item: ItemData

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading) {
                ForEach(item.items, id: \.id) { item in
                    ItemRowView(item: item)
                    Divider().background(.secondary)
                }
            }
            .font(.pixel14)
            .foregroundStyle(.white)
            .padding()
        }
        .applyPokedexStyling(title: item.title?.pretty ?? "Unknown")
    }
}

#Preview {
    ItemDetailView(item: .init(title: "Item", items: [.common]))
}
