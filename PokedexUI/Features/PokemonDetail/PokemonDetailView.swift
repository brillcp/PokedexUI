import SwiftUI
import SwiftData

struct PokemonDetailView<ViewModel: PokemonDetailViewModelProtocol & Sendable>: View {
    // MARK: - Environment Dependencies
    @Environment(\.container) private var container
    @Environment(\.modelContext) private var modelContext

    // MARK: - Data Query
    @Query(
        filter: #Predicate<Pokemon> { $0.isBookmarked },
        sort: \.id
    )
    private var bookmarks: [Pokemon]

    // MARK: - State Management
    @State private var viewModel: ViewModel
    @State private var showOpponentPicker = false
    @State private var battleOpponent: PokemonViewModel?
    @State private var evolutionTarget: PokemonViewModel?

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
                withSpriteLoader: container.spriteLoader,
                imageColorAnalyzer: container.imageColorAnalyzer
            )
        }
        .task(id: viewModel.pokemon.evolutionChainId) {
            await viewModel.loadEvolutionChain()
        }
        .task { await container.typeChart.loadIfNeeded() }
        .onAppear {
            viewModel.updateBookmarkStatus(from: bookmarks)
        }
        .sheet(isPresented: $showOpponentPicker) {
            if let player = viewModel.pokemon as? PokemonViewModel {
                OpponentPickerView(player: player) { opp in
                    showOpponentPicker = false
                    battleOpponent = opp
                }
            }
        }
        .navigationDestination(item: $battleOpponent) { opp in
            if let player = viewModel.pokemon as? PokemonViewModel {
                BattleView(
                    viewModel: BattleViewModel(
                        player: player,
                        opponent: opp,
                        typeChart: container.typeChart,
                        moveService: container.moveService,
                        audioPlayer: container.audioPlayer
                    )
                )
            }
        }
        .navigationDestination(item: $evolutionTarget) { target in
            PokemonDetailView<PokemonDetailViewModel>(
                viewModel: PokemonDetailViewModel(pokemon: target)
            )
        }
        .applyDetailViewStyling(viewModel: viewModel, textColor: textColor, context: modelContext)
    }
}

// MARK: - Main Content Sections
private extension PokemonDetailView {
    var textColor: Color {
        viewModel.color?.isLight ?? false ? .black : .white
    }

    func contentSection() -> some View {
        Group {
            speciesHeader()

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
            DetailRow(title: "Capture", subtitle: capturePercentText)
            GenderRow(rate: viewModel.pokemon.genderRate, textColor: textColor)
            WeaknessGridView(
                pokemon: viewModel.pokemon,
                typeChart: container.typeChart,
                textColor: textColor
            )

            rowSection(title: "Abilities", data: viewModel.pokemon.abilities)
            rowSection(title: "Moves", data: viewModel.pokemon.moves)
            statsSection()
            Divider().foregroundStyle(textColor)
            EvolutionChainView(
                stages: viewModel.evolutionStages,
                textColor: textColor,
                onSelect: navigateToEvolution
            )
            Spacer().frame(height: 96)
        }
        .padding(.horizontal, 24)
        .foregroundStyle(textColor)
        .lineHeight(.loose)
    }

    /// Top header: genus + generation badge.
    func speciesHeader() -> some View {
        HStack {
            if let genus = viewModel.pokemon.genus {
                Text(genus.pretty)
                    .font(.pixel14)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let gen = viewModel.pokemon.generationName?.uppercased().replacingOccurrences(of: "GENERATION-", with: "GEN ") {
                Text(gen)
                    .font(.pixel12)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(textColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            if viewModel.pokemon.isLegendary {
                badgePill("LEGENDARY")
            }
            if viewModel.pokemon.isMythical {
                badgePill("MYTHICAL")
            }
        }
    }

    func badgePill(_ text: String) -> some View {
        Text(text)
            .font(.pixel12)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.pokedexRed.opacity(0.7))
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }

    /// Resolve an evolution stage's species id to a stored `Pokemon` and push the detail view.
    /// Skips navigation if the species isn't in the local SwiftData cache yet.
    func navigateToEvolution(speciesId: Int) {
        guard speciesId != viewModel.pokemon.id else { return }
        let descriptor = FetchDescriptor<Pokemon>(predicate: #Predicate { $0.id == speciesId })
        if let pokemon = try? modelContext.fetch(descriptor).first {
            evolutionTarget = PokemonViewModel(pokemon: pokemon)
        }
    }

    var capturePercentText: String {
        // PokeAPI capture_rate is a 0–255 byte. Convert to a familiar percent.
        let pct = Int(round(Double(viewModel.pokemon.captureRate) / 255.0 * 100.0))
        return "\(viewModel.pokemon.captureRate) (\(pct)%)"
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
            DetailButton(icon: "bolt.fill") {
                showOpponentPicker = true
            }
            Spacer()
            if viewModel.pokemon.latestCry != nil {
                DetailButton(icon: "speaker.wave.3.fill") {
                    Task { await viewModel.playSound(with: container.audioPlayer) }
                }
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
                        viewModel.flipSprite(hapticFeedback: container.haptic)
                    }
                    .onEnded { _ in
                        viewModel.flipSpriteBack(hapticFeedback: container.haptic)
                    }
            )
    }
}

// MARK: - Information Sections
private extension PokemonDetailView {
    func statsSection() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
                .foregroundStyle(textColor)
                .frame(height: 2)
            ForEach(viewModel.pokemon.stats) { stat in
                DetailRowStat(
                    title: stat.stat.name,
                    value: stat.baseStat,
                    color: viewModel.color,
                    textColor: textColor
                )
            }
            HStack {
                Text("TOTAL")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(viewModel.pokemon.baseStatTotal)")
            }
            .font(.pixel14)
            .padding(.top, 4)
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

#Preview {
    let vm = PokemonDetailViewModel(pokemon: PokemonViewModel(pokemon: .pikachu))
    PokemonDetailView(viewModel: vm)
        .colorScheme(.dark)
}
