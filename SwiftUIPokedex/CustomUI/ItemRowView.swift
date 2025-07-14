import SwiftUI

struct ItemRowView: View {
    private let imageLoader: ImageLoader
    private let item: ItemData

    @State private var image: Image?

    init(item: ItemData, imageLoader: ImageLoader = .init()) {
        self.item = item
        self.imageLoader = imageLoader
    }

    var body: some View {
        HStack {
            Group {
                if let image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Color(.darkGray)
                        .clipShape(RoundedRectangle(cornerRadius: 8.0))
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(width: 38.0)

            Text(item.title?.pretty ?? "none")
            Spacer()
            Text(">")
        }
        .padding(.vertical)
        .task { await loadItemSprite() }
    }
}

// MARK: - Private functions
private extension ItemRowView {
    @MainActor
    func loadItemSprite() async {
        guard let sprite = item.items.first?.sprites.default else { return }

        let uiImage = await imageLoader.loadImage(from: sprite)
        image = Image(uiImage: uiImage ?? UIImage())
    }
}

#Preview {
    ItemRowView(item: .init())
}
