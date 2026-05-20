import SwiftUI

/// Single row in the items tab: sprite + pretty name + cost label. Tapping
/// the row navigates to `ItemDetailView`.
struct ItemRowView: View {
    let item: ItemData

    var body: some View {
        HStack(spacing: 16.0) {
            SpriteImage(url: item.icon)
                .frame(width: 38)
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
