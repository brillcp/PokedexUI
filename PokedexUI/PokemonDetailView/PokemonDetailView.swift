import SwiftUI
import SwiftData

struct PokemonDetailView<ViewModel: PokemonDetailViewModelProtocol & Sendable>: View {
    // MARK: - Environment Dependencies
    @Environment(\.hapticFeedback) private var haptic: UIImpactFeedbackGenerator
    @Environment(\.imageColorAnalyzer) private var imageColorAnalyzer
    @Environment(\.audioPlayer) private var audioPlayer: AudioPlayer
    @Environment(\.spriteLoader) private var spriteLoader
    @Environment(\.typeChart) private var typeChart
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
                withSpriteLoader: spriteLoader,
                imageColorAnalyzer: imageColorAnalyzer
            )
        }
        .task(id: viewModel.pokemon.evolutionChainId) {
            await viewModel.loadEvolutionChain()
        }
        .task { await typeChart.loadIfNeeded() }
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
                        typeChart: typeChart
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
                typeChart: typeChart,
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
                    Task { await viewModel.playSound(with: audioPlayer) }
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

// MARK: - Weakness / resistance grid

private struct WeaknessGridView: View {
    let pokemon: PokemonViewModelProtocol
    let typeChart: TypeChartLoader
    let textColor: Color

    /// Bucket attacker types by the multiplier they produce against this pokemon.
    private var buckets: [(label: String, types: [String])] {
        let defenders = pokemon.typeNames
        guard !typeChart.chart.isEmpty else { return [] }

        var rows: [Double: [String]] = [:]
        for (attackerName, _) in typeChart.chart {
            let m = typeChart.multiplier(attacking: attackerName, defenders: defenders)
            guard m != 1.0 else { continue }
            rows[m, default: []].append(attackerName)
        }
        let order: [(Double, String)] = [(4, "×4"), (2, "×2"), (0.5, "×1/2"), (0.25, "×1/4"), (0, "×0")]
        return order.compactMap { mult, label in
            guard let names = rows[mult], !names.isEmpty else { return nil }
            return (label, names.sorted())
        }
    }

    var body: some View {
        if buckets.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Damage Taken")
                    .foregroundStyle(.secondary)
                ForEach(buckets, id: \.label) { row in
                    HStack(alignment: .top, spacing: 12) {
                        Text(row.label)
                            .frame(width: 36, alignment: .leading)
                            .foregroundStyle(textColor)
                        Text(row.types.map { $0.capitalized }.joined(separator: ", "))
                            .foregroundStyle(textColor.opacity(0.85))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Gender ratio bar

private struct GenderRow: View {
    let rate: Int
    let textColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("Gender")
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
            if rate < 0 {
                Text("Genderless")
            } else {
                let female = Double(rate) / 8.0
                let male = 1.0 - female
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { proxy in
                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(Color.blue.opacity(0.7))
                                .frame(width: proxy.size.width * male)
                            Rectangle()
                                .fill(Color.pink.opacity(0.8))
                                .frame(width: proxy.size.width * female)
                        }
                        .clipShape(Capsule())
                    }
                    .frame(height: 10)
                    HStack {
                        Text("♂ \(Int(male * 100))%")
                        Spacer()
                        Text("♀ \(Int(female * 100))%")
                    }
                        .font(.pixel12)
                        .foregroundStyle(textColor.opacity(0.8))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Evolution chain row

private struct EvolutionChainView: View {
    let stages: [EvolutionChain.Stage]
    let textColor: Color
    let onSelect: (Int) -> Void

    var body: some View {
        if stages.count < 2 {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Evolution")
                    .foregroundStyle(.secondary)
                // Full-width row: each stage gets an equal share of the available
                // space (≈ screen/3 when there are 3 stages, screen/2 for 2).
                // Arrows size to their content and sit between the equal columns.
                HStack(alignment: .center, spacing: 0) {
                    ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                        stageCell(stage)
                            .frame(maxWidth: .infinity)
                        if index < stages.count - 1 {
                            arrow(for: stages[index + 1].trigger)
                                .frame(width: 56)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func stageCell(_ stage: EvolutionChain.Stage) -> some View {
        Button {
            if let id = stage.species.id {
                onSelect(id)
            }
        } label: {
            VStack(spacing: 4) {
                if let id = stage.species.id {
                    AsyncImage(url: URL(string: "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/\(id).png")) { image in
                        image.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Color(.systemGray4).clipShape(Circle())
                    }
                    .frame(width: 64, height: 64)
                }
                Text(stage.species.name.capitalized)
                    .font(.pixel12)
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(stage.species.id == nil)
    }

    private func arrow(for detail: EvolutionDetail?) -> some View {
        VStack(spacing: 2) {
            Image(systemName: "arrow.right")
                .font(.pixel14)
                .foregroundStyle(textColor.opacity(0.7))
            if let label = label(for: detail) {
                Text(label)
                    .font(.pixel12)
                    .foregroundStyle(textColor.opacity(0.7))
            }
        }
    }

    private func label(for detail: EvolutionDetail?) -> String? {
        guard let detail else { return nil }
        if let level = detail.minLevel {
            return "Lv \(level)"
        }
        if let item = detail.item?.name {
            return item.replacingOccurrences(of: "-", with: " ").capitalized
        }
        if let trigger = detail.trigger?.name, trigger != "level-up" {
            return trigger.replacingOccurrences(of: "-", with: " ").capitalized
        }
        if (detail.minHappiness ?? 0) > 0 {
            return "Friendship"
        }
        return nil
    }
}

// MARK: - View Modifiers
private extension View {
    func applyDetailViewStyling(viewModel: PokemonDetailViewModelProtocol, textColor: Color, context: ModelContext) -> some View {
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
