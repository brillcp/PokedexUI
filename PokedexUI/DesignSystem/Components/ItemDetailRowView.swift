import SwiftUI

/// Full item row used on the item detail screen: sprite + name + flavor text
/// description. Wider layout than `ItemRowView` to fit the effect blurb.
struct ItemDetailRowView: View {
    let item: ItemDetail

    var body: some View {
        let effect = item.prettyEffect
        HStack(alignment: effect.isEmpty ? .center : .top, spacing: 16.0) {
            SpriteImage(url: item.sprites?.default)
                .frame(width: 38)

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
