import SwiftUI

struct BattleView: View {
    @Environment(\.dismiss) private var dismiss
    @State var viewModel: BattleViewModel

    var body: some View {
        content
            .foregroundStyle(.white)
            .background(Color.darkGrey)
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
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity)
        .overlay {
            if let winner = viewModel.winner {
                endOverlay(winner: winner)
            }
        }
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
        let isAttacking = viewModel.attackingSide == side
        let isFainted = viewModel.faintedSide == side
        let lungeDirection: CGFloat = side == .player ? 1 : -1
        let shakeTick = side == .player ? viewModel.playerShakeTick : viewModel.opponentShakeTick

        return AsyncImage(url: url.flatMap(URL.init(string:))) { image in
            image.resizable().aspectRatio(contentMode: .fit)
        } placeholder: {
            Color(.systemGray4).clipShape(Circle())
        }
        .frame(width: 132, height: 132)
        .modifier(ShakeEffect(animatableData: CGFloat(shakeTick)))
        .offset(x: isAttacking ? lungeDirection * 20 : 0, y: isAttacking ? -10 : 0)
        .scaleEffect(isFainted ? 0.4 : 1)
        .opacity(isFainted ? 0 : 1)
        .animation(.spring(response: 0.35, dampingFraction: 0.5), value: shakeTick)
    }

    private func hpCard(_ c: BattleCombatant) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(c.name)
                    .font(.pixel14)
                if c.status != .none {
                    Text(c.status.displayName)
                        .font(.pixel12)
                        .foregroundStyle(statusColor(c.status))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 4))
                }
            }
            Gauge(value: Double(c.currentHP), in: 0...Double(c.maxHP)) {
                EmptyView()
            } currentValueLabel: { EmptyView() }
            .gaugeStyle(.linearCapacity)
            .tint(hpTint(current: c.currentHP, max: c.maxHP))
            .animation(.easeOut(duration: 0.5), value: c.currentHP)
            Text("\(c.currentHP) / \(c.maxHP)")
                .font(.pixel12)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText(value: Double(c.currentHP)))
                .animation(.easeOut(duration: 0.5), value: c.currentHP)
        }
        .padding(10)
        .frame(width: 180, alignment: .leading)
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 8))
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
        VStack(alignment: .leading, spacing: 4) {
            Text(move.displayName).font(.pixel12)
            HStack(spacing: 8) {
                Text(move.typeName.uppercased())
                    .font(.pixel12)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(typeColor(move.typeName))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                if let pp = move.pp {
                    Text("PP \(pp)").font(.pixel12).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.clear.interactive(), in: RoundedRectangle(cornerRadius: 8))
    }

    private func endOverlay(winner: BattleSide) -> some View {
        let winnerName = winner == .player ? viewModel.playerPokemon.name : viewModel.opponentPokemon.name
        return VStack(spacing: 16) {
            Text("\(winnerName) wins!").font(.pixel17)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
