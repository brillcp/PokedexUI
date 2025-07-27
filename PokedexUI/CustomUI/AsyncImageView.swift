import SwiftUI

struct AsyncImageView<ViewModel: PokemonViewModelProtocol>: View {
    @Binding private var viewModel: ViewModel
    @State private var hasFadedIn = false
    private let showOverlay: Bool

    // MARK: - Init
    init(viewModel: ViewModel, showOverlay: Bool) {
        self._viewModel = .constant(viewModel)
        self.showOverlay = showOverlay
    }

    var body: some View {
        ZStack {
            Color(.darkGray)
            sprite
        }
        .aspectRatio(1.0, contentMode: .fit)
        .cornerRadius(16.0)
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

// A simple View extension to apply a modifier conditionally
private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, modify: (Self) -> Content) -> some View {
        if condition {
            modify(self)
        } else {
            self
        }
    }
}

#Preview {
    AsyncImageView(viewModel: PokemonViewModel(pokemon: .pikachu), showOverlay: false)
}
