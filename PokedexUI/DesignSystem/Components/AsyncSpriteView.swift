import SwiftUI

struct AsyncSpriteView<ViewModel: IdentifiablePokemon>: View {
    // MARK: Private properties
    @Environment(\.container) private var container

    @State private var sprite: Image?
    @State private var color: Color?
    @State private var isLight = false

    // MARK: - Public properties
    let viewModel: ViewModel
    let showOverlay: Bool

    // MARK: - Body
    var body: some View {
        ZStack {
            Color(.systemGray4)
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
                  let uicolor = await container.imageColorAnalyzer.dominantColor(for: viewModel.id, image: image)
            else { return }

            let resolved = Color(uiColor: uicolor)
            isLight = resolved.isLight
            withAnimation(.easeInOut(duration: 0.4)) {
                color = resolved
                sprite = Image(uiImage: image)
            }
        }
    }
}

// MARK: - Private UI components
private extension AsyncSpriteView {
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
        viewModel: PokemonViewModel(pokemon: .pikachu),
        showOverlay: true
    )
}
