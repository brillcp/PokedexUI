import SwiftUI

struct ItemRowView: View {
    let item: ItemData

    var body: some View {
        HStack {
            ItemSpriteView(viewModel: ItemSpriteViewModel(imageURL: item.items.first?.sprites.default ?? ""))
            Text(item.title?.pretty ?? "none")
            Spacer()
            Text(">")
        }
        .padding(.vertical)
    }
}

#Preview {
    ItemRowView(item: .init())
}
