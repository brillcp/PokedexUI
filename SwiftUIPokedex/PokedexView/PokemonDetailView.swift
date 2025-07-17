import SwiftUI

struct PokemonDetailView<ViewModel: PokemonViewModelProtocol>: View {
    let viewModel: ViewModel

    @State private var isFlipped = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    Sprite()
                    ImageOverlay()
                }

                VStack {
                    BasicInfoSection(viewModel: viewModel)
                    SectionDivider()
                    StatsSection(viewModel: viewModel)
                    SectionDivider()
                    MovesSection(viewModel: viewModel)
                    BottomSpacer()
                }
                .padding()
                .background(Color.darkGrey)
                .clipShape(RoundedRectangle(cornerRadius: 32.0))
                .foregroundStyle(.white)
            }
        }
        .applyDetailViewStyling(viewModel: viewModel)
    }
}

// MARK: - Content Sections
private extension PokemonDetailView {
    func Sprite() -> some View {
        Image(uiImage: (isFlipped ? viewModel.backImage : viewModel.frontImage) ?? UIImage())
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: 320)
            .modifier(Perspective3D(isFlipped: $isFlipped))
            .animation(.bouncy(duration: 0.3, extraBounce: 0.1), value: isFlipped)
    }

    func ImageOverlay() -> some View {
        HStack {
            Spacer()
            FlipButton()
        }
        .buttonStyle(.glass)
        .tint(.white)
        .padding()
    }

    func FlipButton() -> some View {
        Button(action: {}) {
            ImageIcon("arrow.trianglehead.2.clockwise")
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            guard !isFlipped else { return }
                            isFlipped = true
                        }
                        .onEnded { _ in
                            guard isFlipped else { return }
                            isFlipped = false
                        }
                )
        }
    }

    func ImageIcon(_ icon: String) -> some View {
        Image(systemName: icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 24, height: 24)
            .padding(8)
    }

    func BasicInfoSection(viewModel: ViewModel) -> some View {
        VStack {
            DetailRow(title: "Types", subtitle: viewModel.types)
            DetailRow(title: "Height", subtitle: viewModel.height)
            DetailRow(title: "Weight", subtitle: viewModel.weight)
            DetailRow(title: "Abilities", subtitle: viewModel.abilities)
        }
    }

    func StatsSection(viewModel: ViewModel) -> some View {
        ForEach(viewModel.stats) { stat in
            DetailRowStat(
                title: stat.stat.name,
                value: stat.baseStat,
                color: viewModel.color
            )
        }
    }

    func MovesSection(viewModel: ViewModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Moves")
                .foregroundStyle(.secondary)
            Text(viewModel.moves)
        }
        .padding(.vertical)
    }

    func SectionDivider() -> some View {
        Divider()
            .background(.secondary)
            .padding(.vertical)
    }

    func BottomSpacer() -> some View {
        Spacer()
            .frame(height: 96)
    }
}

// MARK: - Reusable Row Components
private extension PokemonDetailView {
    func DetailRow(title: String, subtitle: String) -> some View {
        BaseRow(title: title) {
            Text(subtitle)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func DetailRowStat(title: String, value: Int, color: Color?) -> some View {
        let maxValue = max(value, 100)
        let clampedValue = max(value, 0)
        return BaseRow(title: title.capitalized) {
            ProgressView(value: Double(clampedValue), total: Double(maxValue))
                .frame(height: 20)
                .tint(color ?? .white)
            Text("\(clampedValue) / \(maxValue)")
        }
    }

    func BaseRow<Content: View>(
        title: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 20) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(minWidth: 96, alignment: .leading)
            content()
        }
        .padding(.vertical)
    }
}

// MARK: - View Modifiers
private extension View {
    func applyDetailViewStyling<ViewModel: PokemonViewModelProtocol>(
        viewModel: ViewModel
    ) -> some View {
        ZStack {
            VStack(spacing: 0) {
                viewModel.color
                Spacer()
                Color.darkGrey
                    .frame(height: 300)
            }
            .ignoresSafeArea()

            self
                .font(.pixel14)
                .navigationTitle(viewModel.name)
                .toolbar {
                    Text("#\(viewModel.id)")
                }
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

#Preview {
    PokemonDetailView(viewModel: PokemonViewModel(pokemon: .pikachu))
}
