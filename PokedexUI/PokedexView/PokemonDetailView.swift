import SwiftUI
import SwiftData

struct PokemonDetailView<ViewModel: PokemonViewModelProtocol & Sendable>: View {
    // MARK: Private properties
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<Pokemon> { $0.isBookmarked },
        sort: \.id,
        order: .forward
    )
    private var bookmarks: [Pokemon]

    private let haptic: UIImpactFeedbackGenerator
    @State private var viewModel: ViewModel
    @State private var isFlipped = false

    // MARK: - Init
    init(viewModel: ViewModel, haptic: UIImpactFeedbackGenerator = .init(style: .light)) {
        self.viewModel = viewModel
        self.haptic = haptic
        haptic.prepare()
    }

    // MARK: - Body
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    sprite()
                    actionButtons()
                }

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
        }
        .onAppear {
            viewModel.isBookmarked = bookmarks.contains(where: { $0.id == viewModel.id })
        }
        .applyDetailViewStyling(viewModel: viewModel)
    }
}

// MARK: - Content Sections
private extension PokemonDetailView {
    func sprite() -> some View {
        Image(uiImage: (isFlipped ? viewModel.backSprite : viewModel.frontSprite) ?? UIImage())
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: 320)
            .modifier(Perspective3D(isFlipped: $isFlipped))
            .animation(.bouncy(duration: 0.3, extraBounce: 0.1), value: isFlipped)
    }

    func actionButtons() -> some View {
        HStack {
            if let cry = viewModel.latestCry {
                Button {
                    Task { await viewModel.playBattleCry(cry) }
                } label: {
                    imageIcon("speaker.wave.3.fill")
                }
            }
            Spacer()
            Button {
                toggleBookmark()
            } label: {
                imageIcon(viewModel.isBookmarked ? "bookmark.fill" : "bookmark")
            }
            if viewModel.backSprite != nil {
                flipButton()
            }
        }
        .buttonStyle(.glass)
        .tint(.white)
        .padding()
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
                color: viewModel.color
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

// MARK: - Bookmark Toggle
private extension PokemonDetailView {
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
