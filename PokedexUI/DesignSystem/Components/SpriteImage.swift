import SwiftUI

/// Lightweight async sprite loader backed by the shared `SpriteLoader`
/// cache. Shows a circle placeholder until the image lands. Used
/// across battle screens, evolution chains, opponent pickers, and
/// item rows. Optional `onLoaded` callback lets the parent act on the
/// raw `UIImage` (e.g. color analysis) without a redundant cache lookup.
struct SpriteImage: View {
    @Environment(\.container) private var container
    @State private var image: Image?

    let url: String?
    var onLoaded: ((UIImage) async -> Void)?

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .transition(.opacity)
            } else {
                Color.cardBackground
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
