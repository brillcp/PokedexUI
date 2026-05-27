import SwiftUI

/// Async sprite loader backed by the shared `SpriteLoader` cache.
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

// MARK: - Private
private extension SpriteImage {
    @ViewBuilder var placeholder: some View {
        switch style {
        case .circle:
            Color.white.opacity(0.05).clipShape(Circle())
        case .plain:
            Color.white.opacity(0.05)
        }
    }
}
