import SwiftUI

struct AsyncImageView<ViewModel: PokemonViewModelProtocol>: View {
    @State private var hasFadedIn = false

    @State var viewModel: ViewModel
    let showOverlay: Bool

    var body: some View {
        ZStack {
            Color(.darkGray)
            sprite
        }
        .aspectRatio(1.0, contentMode: .fit)
        .task { await viewModel.loadSprite() }
    }
}

// MARK: - Private UI components
private extension AsyncImageView {
    @ViewBuilder
    var sprite: some View {
        if let image = viewModel.frontImage {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .background(viewModel.color)
                .overlay(cardOverlay(for: viewModel))
                .if(!hasFadedIn) { $0.fadeIn(when: image) }
                .onChange(of: viewModel.frontImage) { _, newImage in
                    guard newImage != nil, !hasFadedIn else { return }
                    hasFadedIn = true
                }
        }
    }

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
            .foregroundStyle(pokemon.isLight ? .black : .white)
        }
    }
}

#Preview {
    AsyncImageView(viewModel: PokemonViewModel(pokemon: .pikachu), showOverlay: false)
}
