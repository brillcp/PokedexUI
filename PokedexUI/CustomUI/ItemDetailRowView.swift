import SwiftUI

struct ItemDetailRowView: View {
    let item: ItemDetail

    var body: some View {
        let effect = item.prettyEffect
        HStack(alignment: effect.isEmpty ? .center : .top, spacing: 16.0) {
            ItemSpriteView(spriteURL: item.sprites?.default)

            VStack(alignment: .leading, spacing: 16) {
                Text(item.prettyName)
                if !effect.isEmpty {
                    Text(effect)
                        .foregroundStyle(.secondary)
                        .lineHeight(.loose)
                }
            }
        }
        .padding(.vertical)
    }
}

#Preview {
    ItemDetailRowView(item: .common)
}
