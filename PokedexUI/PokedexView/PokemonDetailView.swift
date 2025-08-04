import SwiftUI
import SwiftData

struct PokemonDetailView<ViewModel: PokemonViewModelProtocol & Sendable>: View {
    // MARK: Environment Dependencies
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
    @State private var isFlipped = false
    @State private var frontSprite: Image?
    @State private var backSprite: Image?
    @State private var color: Color?

    // MARK: - Initialization
    init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - Body
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                spriteSection()
                contentSection()
            }
        }
        .task(id: viewModel.id, loadSpritesAndColor)
        .onAppear(perform: updateBookmarkStatus)
        .applyDetailViewStyling(viewModel: viewModel, color: color)
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
            basicInfoSection(viewModel: viewModel)
            sectionDivider()
            statsSection(viewModel: viewModel)
            sectionDivider()
            movesSection(viewModel: viewModel)
            bottomSpacer()
        }
        .padding()
        .background(Color.darkGrey)
        .foregroundStyle(.white)
    }

    func spriteImage() -> some View {
        (isFlipped ? backSprite : frontSprite)?
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: 320)
            .modifier(Perspective3D(isFlipped: $isFlipped))
            .animation(.bouncy(duration: 0.3, extraBounce: 0.1), value: isFlipped)
    }
}

// MARK: - Action Buttons
private extension PokemonDetailView {
    func actionButtons() -> some View {
        HStack {
            if let cryURL = viewModel.latestCry {
                playSoundButton(cryURL: cryURL)
            }
            Spacer()
            bookmarkButton()
            if viewModel.backSprite != nil {
                flipButton()
            }
        }
        .buttonStyle(.glass)
        .tint(color?.isLight ?? false ? .black : .white)
        .padding()
    }

    func playSoundButton(cryURL: String) -> some View {
        Button {
            Task { await audioPlayer.play(from: cryURL) }
        } label: {
            imageIcon("speaker.wave.3.fill")
        }
    }

    func bookmarkButton() -> some View {
        Button {
            toggleBookmark()
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
    func basicInfoSection(viewModel: ViewModel) -> some View {
        VStack {
            detailRow(title: "Types", subtitle: viewModel.types)
            detailRow(title: "Height", subtitle: viewModel.height)
            detailRow(title: "Weight", subtitle: viewModel.weight)
            detailRow(title: "Abilities", subtitle: viewModel.abilities)
        }
    }

    func statsSection(viewModel: ViewModel) -> some View {
        ForEach(viewModel.stats) { stat in
            detailRowStat(
                title: stat.stat.name,
                value: stat.baseStat,
                color: color
            )
        }
    }

    func movesSection(viewModel: ViewModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Moves")
                .foregroundStyle(.secondary)
            Text(viewModel.moves)
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

// MARK: - Data Operations
private extension PokemonDetailView {
    @Sendable
    func loadSpritesAndColor() async {
        if let image = await spriteLoader.spriteImage(from: viewModel.frontSprite),
           let uicolor = await imageColorAnalyzer.dominantColor(for: viewModel.id, image: image) {
            color = Color(uiColor: uicolor)
            frontSprite = Image(uiImage: image)
            if let back = viewModel.backSprite, let img = await spriteLoader.spriteImage(from: back) {
                backSprite = Image(uiImage: img)
            }
        }
    }

    func updateBookmarkStatus() {
        viewModel.isBookmarked = bookmarks.contains(where: { $0.id == viewModel.id })
    }

    func toggleBookmark() {
        let id = viewModel.id
        let descriptor = FetchDescriptor<Pokemon>(predicate: #Predicate { $0.id == id })

        do {
            if let pokemon = try modelContext.fetch(descriptor).first {
                pokemon.isBookmarked.toggle()
                viewModel.isBookmarked = pokemon.isBookmarked
                try modelContext.save()
            }
        } catch {
            print("Failed to toggle bookmark: \(error)")
        }
    }
}

// MARK: - View Modifiers
private extension View {
    func applyDetailViewStyling<ViewModel: PokemonViewModelProtocol>(
        viewModel: ViewModel,
        color: Color?
    ) -> some View {
        ZStack {
            VStack(spacing: 0) {
                color
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
                            .foregroundStyle(color?.isLight ?? false ? .black : .white)
                    }
                }
        }
        .ignoresSafeArea(edges: .bottom)
    }
}
#Preview {
    PokemonDetailView(viewModel: PokemonViewModel(pokemon: .pikachu))
}
