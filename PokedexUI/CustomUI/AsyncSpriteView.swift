import SwiftUI

struct AsyncSpriteView<ViewModel: PokemonViewModelProtocol>: View {
    // MARK: Private properties
    @Environment(\.imageColorAnalyzer) private var imageColorAnalyzer
    @Environment(\.spriteLoader) private var spriteLoader

    @State private var hasFadedIn = false
    @State private var sprite: Image?
    @State private var color: Color?

    // MARK: - Public properties
    @State var viewModel: ViewModel
    let showOverlay: Bool

    // MARK: - Body
    var body: some View {
        ZStack {
            Color(.darkGray)
            sprite?
                .resizable()
                .aspectRatio(contentMode: .fit)
                .background(color)
                .overlay(cardOverlay(for: viewModel))
                .if(!hasFadedIn) { $0.fadeIn(when: sprite) }
                .onChange(of: sprite) { _, newSprite in
                    guard newSprite != nil, !hasFadedIn else { return }
                    hasFadedIn = true
                }
        }
        .aspectRatio(1.0, contentMode: .fit)
        .task(id: viewModel.id) {
            if let image = await spriteLoader.spriteImage(from: viewModel.frontSprite),
               let uicolor = await imageColorAnalyzer.dominantColor(for: viewModel.id, image: image) {
                color = Color(uiColor: uicolor)
                sprite = Image(uiImage: image)
            }
        }
    }
}

// MARK: - Private UI components
private extension AsyncSpriteView {
    @ViewBuilder
    func cardOverlay(for pokemon: PokemonViewModelProtocol) -> some View {
        if showOverlay {
            VStack {
                HStack {
                    Spacer()
                    Text("#\(pokemon.id)")
                        .padding(8)
                }
                Spacer()
                Text(pokemon.name)
            }
            .padding(.bottom, 10)
            .foregroundStyle(color?.isLight ?? false ? .black : .white)
        }
    }
}

#Preview {
    AsyncSpriteView(viewModel: PokemonViewModel(pokemon: .pikachu), showOverlay: false)
}
