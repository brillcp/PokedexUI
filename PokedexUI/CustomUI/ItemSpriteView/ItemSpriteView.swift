import SwiftUI

struct ItemSpriteView: View {
    // MARK: Private properties
    @Environment(\.spriteLoader) private var spriteLoader
    @State private var image: Image?

    // MARK: - Public properties
    let viewModel: ItemSpriteViewModel

    // MARK: - Boby
    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color(.darkGray)
            }
        }
        .task(id: viewModel.spriteURL) {
            await loadSprite()
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(width: 38.0)
    }
}

// MARK: - Private functions
private extension ItemSpriteView {
    func loadSprite() async {
        guard let uiImage = await spriteLoader.spriteImage(from: viewModel.spriteURL) else { return }
        image = Image(uiImage: uiImage)
    }
}
