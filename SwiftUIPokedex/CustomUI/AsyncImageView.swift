import SwiftUI

struct AsyncImageView<ViewModel: PokemonViewModelProtocol>: View {
    @ObservedObject var viewModel: ViewModel

    var body: some View {
        Group {
            if let image = viewModel.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .background(viewModel.color)
            } else {
                ZStack {
                    Color(.darkGray)
                    ProgressView()
                        .task { await viewModel.loadSprite() }
                        .tint(.white)
                }
            }
        }
        .aspectRatio(1.0, contentMode: .fit)
        .cornerRadius(16.0)
    }
}

#Preview {
    AsyncImageView(viewModel: PokemonViewModel(pokemon: .pikachu))
}
