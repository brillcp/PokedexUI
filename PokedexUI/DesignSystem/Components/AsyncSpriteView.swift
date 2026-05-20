import SwiftUI

/// Grid cell that loads a pokemon sprite asynchronously, fades it in, and
/// optionally overlays the id + name (3-column grid layout shows the overlay,
/// 4-column hides it to save space).
struct AsyncSpriteView: View {
    @Environment(\.container) private var container

    @State private var sprite: Image?
    @State private var color: Color?
    @State private var isLight = false

    let viewModel: Pokemon
    let showOverlay: Bool

    var body: some View {
        ZStack {
            Color.cardBackground
            if let sprite {
                sprite
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .background(color)
                    .overlay {
                        if showOverlay {
                            CardOverlay(
                                id: viewModel.id,
                                name: viewModel.name,
                                isLight: isLight
                            )
                        }
                    }
                    .transition(.opacity)
            }
        }
        .aspectRatio(1.0, contentMode: .fit)
        .task(id: viewModel.id) {
            guard let image = await container.spriteLoader.spriteImage(from: viewModel.frontSprite),
                  let color = await container.imageColorAnalyzer.dominantColor(for: viewModel.id, image: image)
            else { return }

            let resolved = color
            isLight = resolved.isLight
            withAnimation(.easeInOut(duration: 0.4)) {
                self.color = resolved
                sprite = Image(uiImage: image)
            }
        }
    }
}

// MARK: - Private UI components
private extension AsyncSpriteView {
    /// Id pill (top-right) + name (bottom-left) overlaid on the sprite when
    /// the parent grid asks for it. Foreground color flips to black on
    /// light-colored sprite backgrounds for contrast.
    struct CardOverlay: View {
        let id: Int
        let name: String
        let isLight: Bool

        var body: some View {
            VStack {
                HStack {
                    Spacer()
                    Text("#\(id)")
                        .padding(8)
                }
                Spacer()
                Text(name)
            }
            .padding(.bottom, 10)
            .foregroundStyle(isLight ? .black : .white)
        }
    }
}

#Preview {
    AsyncSpriteView(
        viewModel: .pikachu,
        showOverlay: true
    )
}
