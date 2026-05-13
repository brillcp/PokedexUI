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
        ScrollView {
            VStack(spacing: 32) {
                VStack(spacing: 0) {
                    spriteImage()
                    actionButtons()
                }
                contentSection()
            }
        }
        .scrollIndicators(.hidden)
        .task(id: viewModel.pokemon.id) {
            await viewModel.loadSpritesAndColor(
                withSpriteLoader: spriteLoader,
                imageColorAnalyzer: imageColorAnalyzer
            )
        }
        .onAppear {
            viewModel.updateBookmarkStatus(from: bookmarks)
        }
        .applyDetailViewStyling(viewModel: viewModel, textColor: textColor)
    }
}

// MARK: - Main Content Sections
private extension PokemonDetailView {
    var textColor: Color {
        viewModel.color?.isLight ?? false ? .black : .white
    }

    func contentSection() -> some View {
        Group {
            if let flavorText = viewModel.pokemon.flavorText?.pretty {
                Text(flavorText)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(textColor)
                    .background(textColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            DetailRow(title: "Types", subtitle: viewModel.pokemon.types)
            DetailRow(title: "Height", subtitle: viewModel.pokemon.height)
            DetailRow(title: "Weight", subtitle: viewModel.pokemon.weight)

            if let habitat = viewModel.pokemon.habitat {
                DetailRow(title: "Habitat", subtitle: habitat)
            }
            rowSection(title: "Abilities", data: viewModel.pokemon.abilities)
            rowSection(title: "Moves", data: viewModel.pokemon.moves)
            statsSection()
            Spacer().frame(height: 96)
        }
        .padding(.horizontal, 24)
        .foregroundStyle(textColor)
        .lineHeight(.loose)
    }

    func spriteImage() -> some View {
        (viewModel.isFlipped ? viewModel.backSprite : viewModel.frontSprite)?
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: 320)
            .modifier(Perspective3D(isFlipped: $viewModel.isFlipped))
            .animation(.bouncy(duration: 0.25, extraBounce: 0.1), value: viewModel.isFlipped)
    }
}

// MARK: - Action Buttons
private extension PokemonDetailView {
    func actionButtons() -> some View {
        HStack {
            if viewModel.pokemon.latestCry != nil {
                DetailButton(icon: "speaker.wave.3.fill") {
                    Task { await viewModel.playSound(with: audioPlayer) }
                }
            }
            Spacer()
            DetailButton(icon: viewModel.isBookmarked ? "heart.fill" : "heart") {
                viewModel.toggleBookmark(in: modelContext)
            }
            if viewModel.pokemon.backSprite != nil {
                flipButton()
            }
        }
        .tint(textColor)
        .padding(.horizontal, 24)
    }

    func flipButton() -> some View {
        DetailButton(icon: "arrow.trianglehead.2.clockwise") {}
            .simultaneousGesture(
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

// MARK: - Information Sections
private extension PokemonDetailView {
    func statsSection() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
                .foregroundStyle(.secondary)
            ForEach(viewModel.pokemon.stats) { stat in
                DetailRowStat(
                    title: stat.stat.name,
                    value: stat.baseStat,
                    color: viewModel.color,
                    textColor: textColor
                )
            }
        }
    }

    func rowSection(title: String, data: String) -> some View {
        VStack(alignment: .leading) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(data)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Reusable Row Components
private struct DetailButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            imageIcon(icon)
        }
        .glassEffect(.clear.interactive(), in: Circle())
    }

    private func imageIcon(_ icon: String) -> some View {
        Image(systemName: icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 24.0, height: 24.0)
            .padding(10)
    }
}

private struct DetailRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
            Text(subtitle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DetailRowStat: View {
    let title: String
    let value: Int
    let color: Color?
    let textColor: Color

    private var abbreviatedTitle: String {
        switch title.lowercased() {
        case "special-attack": return "SATK"
        case "attack": return "ATK"
        case "hp": return "HP"
        case "speed": return "SPD"
        case "special-defense": return "SDEF"
        case "defense": return "DEF"
        default: return title.capitalized
        }
    }

    var body: some View {
        let maxValue = max(value, 100)
        let clampedValue = max(value, 0)

        HStack {
            Text(abbreviatedTitle)
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
                .lineLimit(1)
            Text("\(clampedValue)")
                .frame(width: 32)
            Gauge(value: Double(clampedValue), in: 0...Double(maxValue)) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            } minimumValueLabel: {
                Text("")
            } maximumValueLabel: {
                Text("\(maxValue)")
            }
            .gaugeStyle(.linearCapacity)
            .tint(textColor)
        }
        .padding(.vertical)
    }
}

// MARK: - View Modifiers
private extension View {
    func applyDetailViewStyling(viewModel: PokemonDetailViewModelProtocol, textColor: Color) -> some View {
        self.font(.pixel14)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("\(viewModel.pokemon.name) #\(viewModel.pokemon.id)")
                        .font(.pixel17)
                        .foregroundStyle(textColor)
                }
            }
            .background {
                LinearGradient(
                    stops: [
                        .init(color: viewModel.color ?? .clear, location: 0.3),
                        .init(color: (viewModel.color ?? .black).mix(with: .black, by: 0.2), location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()
            }
            .ignoresSafeArea(edges: .bottom)
    }
}

#Preview {
    let vm = PokemonDetailViewModel(pokemon: PokemonViewModel(pokemon: .pikachu))
    PokemonDetailView(viewModel: vm)
        .colorScheme(.dark)
}
