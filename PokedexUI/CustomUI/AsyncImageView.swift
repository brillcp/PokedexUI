import SwiftUI

struct AsyncImageView<ViewModel: PokemonViewModelProtocol>: View {
    @State private var opacity: Double = 0.0

    @Binding var viewModel: ViewModel

    var body: some View {
        ZStack {
            Color(.darkGray)

            if let image = viewModel.frontImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .background(viewModel.color)
                    .opacity(opacity)
                    .onAppear {
                        withAnimation {
                            opacity = 1.0
                        }
                    }
            }
        }
        .aspectRatio(1.0, contentMode: .fit)
        .cornerRadius(16.0)
        .overlay(cardOverlay(for: viewModel))
        .animation(.easeInOut(duration: 0.4), value: opacity)
        .task { await viewModel.loadSprite() }
    }
}

// MARK: - Private UI components
private extension AsyncImageView {
    func cardOverlay(for pokemon: any PokemonViewModelProtocol) -> some View {
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
        .opacity(opacity)
    }
}

#Preview {
    AsyncImageView(viewModel: .constant(PokemonViewModel(pokemon: .pikachu)))
}
