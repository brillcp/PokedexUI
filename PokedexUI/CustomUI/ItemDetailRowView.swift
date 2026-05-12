import SwiftUI

struct ItemDetailRowView: View {
    let item: ItemDetail

    var body: some View {
        HStack(alignment: .top) {
            if let sprite = item.sprites?.default {
                ItemSpriteView(viewModel: ItemSpriteViewModel(spriteURL: sprite))
            }

            VStack(alignment: .leading, spacing: 16) {
                Text(item.name.pretty)
                Text(item.effect.first?.effect.pretty ?? "")
                    .foregroundStyle(.secondary)
                    .lineHeight(.loose)
            }
        }
        .padding(.vertical)
    }
}

#Preview {
    ItemDetailRowView(item: .common)
}
