import SwiftUI

struct ItemDetailRowView: View {
    let item: ItemDetail

    var body: some View {
        HStack(alignment: .top) {
            ItemSpriteView(viewModel: ItemSpriteViewModel(spriteURL: item.sprites.default))

            VStack(alignment: .leading, spacing: 16) {
                Text(item.name.pretty)
                Text(item.effect.first?.effect.pretty ?? "")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical)
    }
}

#Preview {
    ItemDetailRowView(item: .common)
}
