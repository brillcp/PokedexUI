import SwiftUI
import SwiftData
import PokeBattleKit

/// Lobby screen for two-device multipeer battles. Walks the user through
/// discovery, role selection, pokemon + move pick, and finally hands off
/// to `BattleView` once both peers have submitted their loadouts.
struct MultiplayerSetupView: View {
    @Environment(\.container) private var container
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel: MultiplayerSetupViewModel
    @Query(sort: \Pokemon.id) private var allPokemon: [Pokemon]

    init(container: AppContainer) {
        _viewModel = State(initialValue: MultiplayerSetupViewModel(container: container))
    }

    var body: some View {
        NavigationStack {
            content
                .applyPokedexStyling(title: "Local Battle", color: .darkGrey)
                .foregroundStyle(.white)
                .task { viewModel.startListening() }
                .navigationDestination(item: $viewModel.launch) { launch in
                    BattleView(viewModel: launch.viewModel)
                }
                .alert(
                    "Invitation",
                    isPresented: pendingInvitationBinding,
                    presenting: viewModel.pendingInvitation
                ) { invite in
                    Button("Accept") { viewModel.acceptInvitation() }
                    Button("Decline", role: .cancel) { viewModel.declineInvitation() }
                } message: { invite in
                    Text("\(invite.peerName) wants to battle.")
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            viewModel.cancel()
                            dismiss()
                        }
                    }
                }
        }
    }
}

// MARK: - Private
private extension MultiplayerSetupView {
    var pendingInvitationBinding: Binding<Bool> {
        Binding(
            get: { viewModel.pendingInvitation != nil },
            set: { _ in }
        )
    }

    @ViewBuilder
    var content: some View {
        phaseView
            .onChange(of: viewModel.isConnected) { _, connected in
                if connected { viewModel.phase = .picking }
            }
//            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    var phaseView: some View {
        switch viewModel.phase {
        case .menu:                menuView
        case .hosting:             hostingView
        case .browsing:            browsingView
        case .connecting:          loadingView(message: "Connecting…")
        case .picking:             pickerView
        case .waitingForOpponent:  loadingView(message: "Waiting for opponent…")
        case .launching:           loadingView(message: "Starting battle…")
        case .error(let message):  errorView(message)
        }
    }

    var menuView: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "person.2.wave.2.fill")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Battle a nearby trainer")
                .font(.pixel14)
            Spacer()
            VStack(spacing: 12) {
                PrimaryCapsuleButton(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "Host",
                    isEnabled: true,
                    isLoading: false,
                    action: viewModel.startHosting
                )
                PrimaryCapsuleButton(
                    icon: "magnifyingglass",
                    title: "Browse",
                    isEnabled: true,
                    isLoading: false,
                    action: viewModel.startBrowsing
                )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    var hostingView: some View {
        VStack(spacing: 16) {
            PixelSpinner()
            Text("Advertising as \(viewModel.multipeer.localDisplayName)")
                .font(.pixel14)
            Text("Waiting for a trainer to invite you…")
                .font(.pixel12)
                .foregroundStyle(.secondary)
            Spacer()
            connectedHint
        }
        .padding()
    }

    var browsingView: some View {
        VStack(spacing: 12) {
            Text("Nearby trainers")
                .font(.pixel12)
                .foregroundStyle(.secondary)
            if viewModel.discoveredPeers.isEmpty {
                PixelSpinner()
                Text("Searching…")
                    .font(.pixel14)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(viewModel.discoveredPeers) { peer in
                            Button {
                                viewModel.invite(peer)
                            } label: {
                                HStack {
                                    Image(systemName: "person.fill")
                                    Text(peer.name)
                                        .font(.pixel14)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.secondary)
                                }
                                .padding()
                                .background(Color.cardBackground)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
            Spacer()
            connectedHint
        }
    }

    var pickerView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                pokemonPicker
                if let selected = viewModel.selectedPokemon {
                    selectedSummary(selected)
                    movePicker
                }
            }
            .padding(.horizontal)
        }
        .safeAreaBar(edge: .bottom) { submitButton }
    }

    var pokemonPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pick your pokemon")
                .font(.pixel12)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(allPokemon, id: \.id) { pokemon in
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) {
                                viewModel.selectPokemon(pokemon)
                            }
                        } label: {
                            VStack(spacing: 4) {
                                SpriteImage(url: pokemon.frontSprite)
                                    .frame(width: 64, height: 64)
                                Text(pokemon.name)
                                    .font(.pixel9)
                                    .lineLimit(1)
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(isSelected(pokemon) ? Color.cardBackground.opacity(0.8) : Color.cardBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(isSelected(pokemon) ? Color.white : .clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    func selectedSummary(_ pokemon: Pokemon) -> some View {
        HStack(spacing: 12) {
            SpriteImage(url: pokemon.frontSprite)
                .frame(width: 80, height: 80)
            VStack(alignment: .leading, spacing: 4) {
                Text(pokemon.name)
                    .font(.pixel14)
                HStack(spacing: 4) {
                    ForEach(pokemon.types) { type in
                        Chip(
                            type.type.name.uppercased(),
                            style: .custom(background: TypeColor.color(for: type.type.name))
                        )
                    }
                }
            }
            Spacer()
        }
        .padding()
        .background(Color.cardBackground)
    }

    var movePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Pick \(viewModel.maxSelections) moves")
                    .font(.pixel12)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(viewModel.selectedMoveNames.count)/\(viewModel.maxSelections)")
                    .font(.pixel12)
                    .foregroundStyle(.secondary)
            }
            let spacing: CGFloat = 2
            let columns = [
                GridItem(.flexible(), spacing: spacing),
                GridItem(.flexible(), spacing: spacing)
            ]
            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(viewModel.movePool, id: \.name) { move in
                    moveCard(move)
                }
            }
        }
    }

    func moveCard(_ move: Move) -> some View {
        let selected = viewModel.selectedMoveNames.contains(move.name)
        let atCap = !selected && viewModel.selectedMoveNames.count >= viewModel.maxSelections
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                viewModel.toggleMove(move)
            }
        } label: {
            MoveCell(move: move, mode: .loadout(selected: selected), effectiveness: nil)
        }
        .buttonStyle(.plain)
        .opacity(atCap ? Opacity.disabled : 1)
        .disabled(atCap)
    }

    var submitButton: some View {
        let ready = viewModel.selectedPokemon != nil
            && viewModel.selectedMoveNames.count == viewModel.maxSelections
        return PrimaryCapsuleButton(
            icon: "bolt.fill",
            title: ready ? "Send loadout" : "Pick \(viewModel.maxSelections - viewModel.selectedMoveNames.count) more",
            isEnabled: ready,
            isLoading: false,
            action: viewModel.submitLoadout
        )
        .padding(.horizontal, 24)
    }

    func loadingView(message: String) -> some View {
        VStack(spacing: 16) {
            PixelSpinner()
            Text(message)
                .font(.pixel14)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text(message)
                .font(.pixel14)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            PrimaryCapsuleButton(
                icon: "arrow.uturn.backward",
                title: "Back",
                isEnabled: true,
                isLoading: false,
                action: viewModel.cancel
            )
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var connectedHint: some View {
        Group {
            if case .connecting(let name) = viewModel.connectionState {
                Text("Connecting to \(name)…")
                    .font(.pixel12)
                    .foregroundStyle(.secondary)
            }
        }
    }

    func isSelected(_ pokemon: Pokemon) -> Bool {
        viewModel.selectedPokemon?.id == pokemon.id
    }
}
