import SwiftUI

struct AsyncImageView<ViewModel: PokemonViewModelProtocol>: View {
    @State var viewModel: ViewModel

    var body: some View {
        ZStack {
            Color(.darkGray)

            if let image = viewModel.frontImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .background(viewModel.color)
                    .fadeIn(when: viewModel.frontImage)
            }
        }
        .aspectRatio(1.0, contentMode: .fit)
        .cornerRadius(16.0)
        .overlay(cardOverlay(for: viewModel))
        .task { await viewModel.loadSprite() }
    }
}

// MARK: - Private UI components
private extension AsyncImageView {
    func cardOverlay(for pokemon: PokemonViewModelProtocol) -> some View {
        VStack {
            HStack {
                Spacer()
                Text("#\(pokemon.id)")
                    .foregroundColor(pokemon.isLight ? .black : .white)
                    .padding(8)
            }
            Spacer()
            Text(pokemon.name)
                .foregroundStyle(pokemon.isLight ? .black : .white)
        }
        .padding(.bottom, 10)
        .fadeIn(when: viewModel.frontImage)
    }
}

#Preview {
    AsyncImageView(viewModel: PokemonViewModel(pokemon: .pikachu))
}
