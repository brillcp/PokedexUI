import SwiftUI

struct ItemRowView: View {
    let item: ItemData

    var body: some View {
        HStack(spacing: 16.0) {
            ItemSpriteView(spriteURL: item.icon)
            Text(item.prettyTitle)
            Spacer()
            Text(">")
        }
        .padding(.vertical)
    }
}

#Preview {
    ItemRowView(item: .init(title: "", items: []))
}
