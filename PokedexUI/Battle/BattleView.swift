import SwiftUI

struct BattleView: View {
    @Environment(\.dismiss) private var dismiss
    @State var viewModel: BattleViewModel

    var body: some View {
        content
            .foregroundStyle(.white)
            .background(Color.darkGrey.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("\(viewModel.playerPokemon.name) vs \(viewModel.opponentPokemon.name)")
                        .font(.pixel17)
                        .foregroundStyle(.white)
                }
            }
            .toolbarBackground(Color.darkGrey ?? .black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .task { await viewModel.prepare() }
            .sensoryFeedback(.impact(weight: .medium), trigger: viewModel.attackTick)
            .sensoryFeedback(.success, trigger: viewModel.opponentShakeTick)
            .sensoryFeedback(.error, trigger: viewModel.playerShakeTick)
            .sensoryFeedback(trigger: viewModel.winner) { _, new in
                switch new {
                case .player: return .success
                case .opponent: return .error
                case .none: return nil
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoadingMoves {
            ProgressView("Loading moves…").tint(.white)
        } else if let error = viewModel.errorMessage {
            Text(error).padding()
        } else if let state = viewModel.state {
            battleLayout(state: state)
        }
    }

    private func battleLayout(state: BattleState) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            arena(state: state)
                .padding(.bottom, 16)
            logFeed
            moveGrid(state: state)
                .padding(.top, 0)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 23)
        .frame(maxHeight: .infinity)
    }

    /// Classic Gameboy-style layout: opponent top-right with HP top-left,
    /// player bottom-left (back sprite) with HP bottom-right.
    private func arena(state: BattleState) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                hpCard(state.opponent)
                Spacer(minLength: 12)
                sprite(url: state.opponent.frontSpriteURL, side: .opponent)
            }
            HStack(alignment: .bottom) {
                sprite(url: state.player.backSpriteURL ?? state.player.frontSpriteURL, side: .player)
                Spacer(minLength: 12)
                hpCard(state.player)
            }
        }
    }

    private func sprite(url: String?, side: BattleSide) -> some View {
        BattlerSprite(
            url: url,
            side: side,
            isAttacking: viewModel.attackingSide == side,
            isFainted: viewModel.faintedSide == side,
            hasEntered: viewModel.hasEntered,
            shakeTick: side == .player ? viewModel.playerShakeTick : viewModel.opponentShakeTick,
            isWinner: viewModel.winner == side
        )
    }

    private func hpCard(_ c: BattleCombatant) -> some View {
        HPCard(
            name: c.name,
            currentHP: c.currentHP,
            maxHP: c.maxHP,
            status: c.status
        )
        .equatable()
    }

    /// GameBoy-style fixed window — always 8 lines tall, showing the most recent 8.
    /// Pads the top with empty rows when there are fewer entries so the window never reflows.
    private var logFeed: some View {
        let lineCount = 8
        let lineHeight: CGFloat = 16
        let recent = Array(viewModel.log.suffix(lineCount))
        let padded = Array(repeating: "", count: max(0, lineCount - recent.count)) + recent
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(padded.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.pixel12)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(height: lineHeight, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.bottom, 16)
    }

    private func moveGrid(state: BattleState) -> some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        let disabled = viewModel.isResolvingTurn || viewModel.winner != nil
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(state.player.moves, id: \.name) { move in
                Button {
                    Task { await viewModel.submit(move) }
                } label: {
                    moveLabel(move)
                }
                .disabled(disabled)
            }
        }
        .opacity(disabled ? 0.35 : 1)
        .animation(.easeInOut(duration: 0.2), value: disabled)
    }

    private func moveLabel(_ move: MoveDetail) -> some View {
        MoveLabel(
            name: move.displayName,
            typeName: move.typeName,
            pp: move.pp,
            typeColor: typeColor(move.typeName)
        )
        .equatable()
    }

    private func hpTint(current: Int, max: Int) -> Color {
        let ratio = Double(current) / Double(max)
        if ratio > 0.5 { return .green }
        if ratio > 0.2 { return .yellow }
        return .red
    }

    private func statusColor(_ status: BattleStatus) -> Color {
        switch status {
        case .paralysis: return .yellow
        case .burn: return .orange
        case .poison: return .purple
        case .none: return .clear
        }
    }

    private func typeColor(_ name: String) -> Color {
        switch name {
        case "fire": return .orange
        case "water": return .blue
        case "grass": return .green
        case "electric": return .yellow
        case "psychic": return .pink
        case "ice": return .cyan
        case "fighting", "rock", "ground": return .brown
        case "poison", "ghost": return .purple
        case "flying", "fairy": return .mint
        case "bug": return .green.opacity(0.7)
        case "steel": return .gray
        case "dark": return .black
        case "dragon": return .indigo
        default: return .gray
        }
    }
}

// MARK: - Equatable subviews
// Extracted so SwiftUI's diffing can skip re-rendering them when their inputs
// haven't changed (e.g. during opponent shake animations the player HP card
// doesn't need to redraw).

private struct HPCard: View, Equatable {
    let name: String
    let currentHP: Int
    let maxHP: Int
    let status: BattleStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name).font(.pixel14)
                if status != .none {
                    Text(status.displayName)
                        .font(.pixel10)
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 4))
                }
            }
            Gauge(value: Double(currentHP), in: 0...Double(maxHP)) {
                EmptyView()
            } currentValueLabel: { EmptyView() }
            .gaugeStyle(.linearCapacity)
            .tint(hpTint)
            .animation(.easeOut(duration: 0.5), value: currentHP)
            Text("\(currentHP) / \(maxHP)")
                .font(.pixel12)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText(value: Double(currentHP)))
                .animation(.easeOut(duration: 0.5), value: currentHP)
        }
        .padding(10)
        .frame(width: 180, alignment: .leading)
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 8))
    }

    private var hpTint: Color {
        let ratio = Double(currentHP) / Double(maxHP)
        if ratio > 0.5 { return .green }
        if ratio > 0.2 { return .yellow }
        return .red
    }

    private var statusColor: Color {
        switch status {
        case .paralysis: return .yellow
        case .burn: return .orange
        case .poison: return .purple
        case .none: return .clear
        }
    }
}

private struct MoveLabel: View, Equatable {
    let name: String
    let typeName: String
    let pp: Int?
    let typeColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.pixel12)
            HStack(spacing: 8) {
                Text(typeName.uppercased())
                    .font(.pixel10)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(typeColor)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                if let pp {
                    Text("PP \(pp)").font(.pixel12).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.clear.interactive(), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Sprite

/// One combatant's sprite. Owns the celebration state so the rotation can
/// repeat indefinitely after victory without leaking a Timer into the view model.
private struct BattlerSprite: View {
    let url: String?
    let side: BattleSide
    let isAttacking: Bool
    let isFainted: Bool
    let hasEntered: Bool
    let shakeTick: Int
    let isWinner: Bool

    @State private var celebratingTilt: Double = 0

    /// Off-screen entry: player from left (negative), opponent from right (positive).
    /// Faint slide: player flies further off-left, opponent off-right.
    private var entryOffset: CGFloat {
        if isFainted {
            return side == .player ? -600 : 600
        }
        return hasEntered ? 0 : (side == .player ? -260 : 260)
    }

    /// Attack lunge — toward the opponent. Player lunges up-right, opponent down-left.
    private var lungeOffset: CGSize {
        guard isAttacking else { return .zero }
        return side == .player ? CGSize(width: 20, height: -10) : CGSize(width: -20, height: 10)
    }

    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { image in
            image.resizable().aspectRatio(contentMode: .fit)
        } placeholder: {
            Color(.systemGray4).clipShape(Circle())
        }
        .frame(width: 168, height: 168)
        .modifier(ShakeEffect(animatableData: CGFloat(shakeTick)))
        .rotationEffect(.degrees(celebratingTilt))
        .offset(
            x: lungeOffset.width + entryOffset,
            y: lungeOffset.height
        )
        .opacity(isFainted ? 0 : 1)
        .animation(.spring(response: 0.35, dampingFraction: 0.5), value: shakeTick)
        .animation(.easeOut(duration: 0.5), value: isFainted)
        .onChange(of: isWinner) { _, newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 0.35).repeatForever(autoreverses: true)) {
                    celebratingTilt = 12
                }
            } else {
                withAnimation { celebratingTilt = 0 }
            }
        }
    }
}

/// Horizontal sine-wave shake driven by a monotonically increasing tick.
/// Increment the tick once per damage event; SwiftUI animates the transition,
/// producing a quick wobble that returns to rest.
private struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 8
    var shakes: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = amount * sin(animatableData * .pi * shakes)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}
