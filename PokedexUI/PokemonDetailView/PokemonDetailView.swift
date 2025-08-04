import SwiftUI
import SwiftData

struct PokemonDetailView<ViewModel: PokemonDetailViewModelProtocol & Sendable>: View {
    // MARK: - Environment Dependencies
    @Environment(\.hapticFeedback) private var haptic: UIImpactFeedbackGenerator
    @Environment(\.imageColorAnalyzer) private var imageColorAnalyzer
    @Environment(\.audioPlayer) private var audioPlayer: AudioPlayer
    @Environment(\.spriteLoader) private var spriteLoader
    @Environment(\.modelContext) private var modelContext

    // MARK: - Data Query
    @Query(
        filter: #Predicate<Pokemon> { $0.isBookmarked },
        sort: \.id
    )
    private var bookmarks: [Pokemon]

    // MARK: - State Management
    @State private var viewModel: ViewModel

    // MARK: - Initialization
    init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - Main Body
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                spriteSection()
                contentSection()
            }
        }
        .task(id: viewModel.pokemon.id) {
            await viewModel.loadSpritesAndColor(
                withSpriteLoader: spriteLoader,
                imageColorAnalyzer: imageColorAnalyzer
            )
        }
        .onAppear {
            viewModel.updateBookmarkStatus(from: bookmarks)
        }
        .applyDetailViewStyling(viewModel: viewModel)
    }
}

// MARK: - Main Content Sections
private extension PokemonDetailView {
    func spriteSection() -> some View {
        ZStack(alignment: .bottom) {
            spriteImage()
            actionButtons()
        }
    }

    func contentSection() -> some View {
        VStack {
            basicInfoSection()
            sectionDivider()
            statsSection()
            sectionDivider()
            movesSection()
            bottomSpacer()
        }
        .padding()
        .background(Color.darkGrey)
        .foregroundStyle(.white)
    }

    func spriteImage() -> some View {
        (viewModel.isFlipped ? viewModel.backSprite : viewModel.frontSprite)?
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: 320)
            .modifier(Perspective3D(isFlipped: $viewModel.isFlipped))
            .animation(.bouncy(duration: 0.3, extraBounce: 0.1), value: viewModel.isFlipped)
    }
}

// MARK: - Action Buttons
private extension PokemonDetailView {
    func actionButtons() -> some View {
        HStack {
            if viewModel.pokemon.latestCry != nil {
                playSoundButton()
            }
            Spacer()
            bookmarkButton()
            if viewModel.pokemon.backSprite != nil {
                flipButton()
            }
        }
        .buttonStyle(.glass)
        .tint(viewModel.color?.isLight ?? false ? .black : .white)
        .padding()
    }

    func playSoundButton() -> some View {
        Button {
            Task { await viewModel.playSound(with: audioPlayer) }
        } label: {
            imageIcon("speaker.wave.3.fill")
        }
    }

    func bookmarkButton() -> some View {
        Button {
            viewModel.toggleBookmark(in: modelContext)
        } label: {
            imageIcon(viewModel.isBookmarked ? "bookmark.fill" : "bookmark")
        }
    }

    func flipButton() -> some View {
        Button(action: {}) {
            imageIcon("arrow.trianglehead.2.clockwise")
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            viewModel.flipSprite(hapticFeedback: haptic)
                        }
                        .onEnded { _ in
                            viewModel.flipSpriteBack(hapticFeedback: haptic)
                        }
                )
        }
    }

    func imageIcon(_ icon: String) -> some View {
        Image(systemName: icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 22, height: 22)
            .padding(6)
    }
}

// MARK: - Information Sections
private extension PokemonDetailView {
    func basicInfoSection() -> some View {
        VStack {
            detailRow(title: "Types", subtitle: viewModel.pokemon.types)
            detailRow(title: "Height", subtitle: viewModel.pokemon.height)
            detailRow(title: "Weight", subtitle: viewModel.pokemon.weight)
            detailRow(title: "Abilities", subtitle: viewModel.pokemon.abilities)
        }
    }

    func statsSection() -> some View {
        ForEach(viewModel.pokemon.stats) { stat in
            detailRowStat(
                title: stat.stat.name,
                value: stat.baseStat,
                color: viewModel.color
            )
        }
    }

    func movesSection() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Moves")
                .foregroundStyle(.secondary)
            Text(viewModel.pokemon.moves)
        }
        .padding(.vertical)
    }
}

// MARK: - Layout Helpers
private extension PokemonDetailView {
    func sectionDivider() -> some View {
        Divider()
            .background(.secondary)
            .padding(.vertical)
    }

    func bottomSpacer() -> some View {
        Spacer()
            .frame(height: 96)
    }
}

// MARK: - Reusable Row Components
private extension PokemonDetailView {
    func detailRow(title: String, subtitle: String) -> some View {
        baseRow(title: title) {
            Text(subtitle)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func detailRowStat(title: String, value: Int, color: Color?) -> some View {
        let maxValue = max(value, 100)
        let clampedValue = max(value, 0)
        return baseRow(title: title.capitalized) {
            ProgressView(value: Double(clampedValue), total: Double(maxValue))
                .frame(height: 20)
                .tint(color ?? .white)
            Text("\(clampedValue) / \(maxValue)")
        }
    }

    func baseRow<Content: View>(
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
    func applyDetailViewStyling(viewModel: PokemonDetailViewModelProtocol) -> some View {
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
                        Text("\(viewModel.pokemon.name) #\(viewModel.pokemon.id)")
                            .font(.pixel17)
                            .foregroundStyle(viewModel.color?.isLight ?? false ? .black : .white)
                    }
                }
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

#Preview {
    let vm = PokemonDetailViewModel(pokemon: PokemonViewModel(pokemon: .pikachu))
    PokemonDetailView(viewModel: vm)
}
