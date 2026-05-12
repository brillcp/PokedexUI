import SwiftUI

struct ItemDetailRowView: View {
    let item: ItemDetail

    private var effect: String? {
        item.effect.first?.effect.pretty
    }

    var body: some View {
        HStack(alignment: effect != nil ? .top : .center, spacing: 16.0) {
            ItemSpriteView(viewModel: ItemSpriteViewModel(spriteURL: item.sprites?.default))

            VStack(alignment: .leading, spacing: 16) {
                Text(item.name.pretty)
                if let effect, !effect.isEmpty {
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
