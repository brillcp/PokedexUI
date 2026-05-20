import SwiftUI

/// Lightweight async sprite loader backed by the shared `SpriteLoader`
/// cache. Shows a placeholder until the image lands. Used across battle
/// screens, evolution chains, opponent pickers, and item rows. Optional
/// `onLoaded` callback lets the parent act on the raw `UIImage` (e.g.
/// color analysis) without a redundant cache lookup.
struct SpriteImage: View {
    enum Style { case circle, plain }

    @Environment(\.container) private var container
    @State private var image: Image?

    let url: String?
    var style: Style = .circle
    var onLoaded: ((UIImage) async -> Void)?

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .transition(.opacity)
            } else {
                placeholder
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .task(id: url) {
            guard let url,
                  let uiImage = await container.spriteLoader.spriteImage(from: url)
            else { return }
            await onLoaded?(uiImage)
            withAnimation(.easeInOut(duration: 0.2)) {
                image = Image(uiImage: uiImage)
            }
        }
    }
}

private extension SpriteImage {
    @ViewBuilder var placeholder: some View {
        switch style {
        case .circle:
            Color.cardBackground.clipShape(Circle())
        case .plain:
            Color.cardBackground
        }
    }
}
