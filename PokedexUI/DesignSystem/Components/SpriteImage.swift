import SwiftUI

/// Lightweight async sprite loader backed by the shared `SpriteLoader`
/// cache. Shows a circle placeholder until the image lands. Used
/// across battle screens, evolution chains, opponent pickers, and
/// item rows.
struct SpriteImage: View {
    @Environment(\.container) private var container
    @State private var image: Image?

    let url: String?

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
            withAnimation(.easeInOut(duration: 0.2)) {
                image = Image(uiImage: uiImage)
            }
        }
    }
}
