import SwiftUI

struct ItemRowView: View {
    let item: ItemData

    var body: some View {
        HStack(spacing: 16.0) {
            ItemSpriteView(viewModel: ItemSpriteViewModel(spriteURL: spriteURL))
            Text(item.title.pretty)
            Spacer()
            Text(">")
        }
        .padding(.vertical)
    }
}

// MARK: - Private calculated properties
private extension ItemRowView {
    var spriteURL: String {
        item.icon ?? ""
    }
}

#Preview {
    ItemRowView(item: .init(title: "", items: []))
}
