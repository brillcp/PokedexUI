import SwiftUI

struct PokemonDetailView<ViewModel: PokemonViewModelProtocol & Sendable>: View {
    private let haptic: UIImpactFeedbackGenerator
    private let viewModel: ViewModel

    @State private var isFlipped = false

    init(viewModel: ViewModel, haptic: UIImpactFeedbackGenerator = .init(style: .light)) {
        self.viewModel = viewModel
        self.haptic = haptic
        haptic.prepare()
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    Sprite()
                    ActionButtons()
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

    func ActionButtons() -> some View {
        HStack {
            if let cry = viewModel.latestCry {
                Button {
                    Task { await viewModel.playSound(cry) }
                } label: {
                    ImageIcon("speaker.wave.3.fill")
                }
            }
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
                            haptic.impactOccurred()
                        }
                        .onEnded { _ in
                            guard isFlipped else { return }
                            isFlipped = false
                            haptic.impactOccurred()
                        }
                )
        }
    }

    func ImageIcon(_ icon: String) -> some View {
        Image(systemName: icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 22, height: 22)
            .padding(6)
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
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("\(viewModel.name) #\(viewModel.id)")
                            .font(.pixel17)
                            .foregroundStyle(viewModel.isLight ? .black : .white)
                    }
                }
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

#Preview {
    PokemonDetailView(viewModel: PokemonViewModel(pokemon: .pikachu))
}
