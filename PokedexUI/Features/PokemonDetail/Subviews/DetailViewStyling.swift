import SwiftUI
import SwiftData

extension View {
    func applyDetailViewStyling(
        viewModel: PokemonDetailViewModelProtocol,
        textColor: Color,
        context: ModelContext
    ) -> some View {
        self.font(.pixel14)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("\(viewModel.pokemon.name) #\(viewModel.pokemon.id)")
                        .font(.pixel17)
                        .foregroundStyle(textColor)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.toggleBookmark(in: context)
                    } label: {
                        Image(systemName: viewModel.isBookmarked ? "heart.fill" : "heart")
                            .foregroundStyle(textColor)
                    }
                }
            }
            .background {
                LinearGradient(
                    stops: [
                        .init(color: viewModel.color ?? .clear, location: 0.4),
                        .init(color: (viewModel.color ?? .black).mix(with: .black, by: 0.2), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
    }
}
