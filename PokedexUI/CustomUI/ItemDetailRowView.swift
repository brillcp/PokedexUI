import SwiftUI

struct ItemDetailRowView: View {
    private let imageLoader = ImageLoader()

    @State private var image: Image?

    let item: ItemDetail

    var body: some View {
        HStack(alignment: .top) {
            sprite

            VStack(alignment: .leading, spacing: 16) {
                Text(item.name.pretty)
                Text(item.effect.first?.description ?? "")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical)
        .task { image = await loadImage() }
    }
}

// MARK: - Private properties
private extension ItemDetailRowView {
    @ViewBuilder
    var sprite: some View {
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
    }

    func loadImage() async -> Image {
        let uiImage = await imageLoader.loadImage(from: item.sprites.default)
        return Image(uiImage: uiImage ?? UIImage())
    }
}

#Preview {
    ItemDetailRowView(item: .common)
}
