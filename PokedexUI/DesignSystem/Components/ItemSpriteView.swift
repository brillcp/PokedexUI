import SwiftUI

/// Small circular sprite used by item rows. Loads asynchronously via the
/// shared `SpriteLoader` actor; renders a gray circle placeholder until the
/// image lands.
struct ItemSpriteView: View {
    // MARK: Private properties
    @Environment(\.container) private var container
    @State private var image: Image?

    // MARK: - Public properties
    let spriteURL: String?

    // MARK: - Body
    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color(.systemGray4)
                    .clipShape(Circle())
            }
        }
        .task(id: spriteURL) {
            await loadSprite()
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(width: 38.0)
    }
}

// MARK: - Private functions
private extension ItemSpriteView {
    func loadSprite() async {
        guard let url = spriteURL,
              let uiImage = await container.spriteLoader.spriteImage(from: url)
        else { return }
        image = Image(uiImage: uiImage)
    }
}
