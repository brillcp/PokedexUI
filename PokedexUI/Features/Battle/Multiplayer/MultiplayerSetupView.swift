import SwiftUI
import SwiftData
import PokeBattleKit

/// Versus tab root. Shows nearby trainers via MultipeerConnectivity.
/// Tapping a trainer invites them; on connect a sheet walks both
/// players through pokemon + move selection before launching the battle.
struct MultiplayerSetupView: View {
    @Environment(\.container) private var container

    @State private var viewModel: MultiplayerSetupViewModel

    init(container: AppContainer) {
        _viewModel = State(initialValue: MultiplayerSetupViewModel(container: container))
    }

    var body: some View {
        NavigationStack {
            discoveryView
                .applyPokedexStyling(title: "Local Battle", color: .darkGrey)
                .foregroundStyle(.white)
                .task { viewModel.startListening() }
                .onAppear { viewModel.startDiscovery() }
                .onDisappear { viewModel.stopDiscovery() }
                .onChange(of: viewModel.isConnected) { _, connected in
                    if connected { viewModel.showPicker = true }
                }
                .onChange(of: viewModel.connectionState) { _, newState in
                    guard newState == .idle else { return }
                    if viewModel.phase == .connecting {
                        viewModel.inviteDeclined()
                    }
                }
                .sheet(isPresented: $viewModel.showPicker, onDismiss: {
                    viewModel.pickerDismissed()
                }) {
                    MultiplayerPickerSheet(viewModel: viewModel)
                }
                .navigationDestination(item: $viewModel.launch) { launch in
                    BattleView(viewModel: launch.viewModel)
                }
                .onChange(of: viewModel.launch) { old, new in
                    if old != nil, new == nil { viewModel.returnToLobby() }
                }
                .alert(
                    "Invitation",
                    isPresented: pendingInvitationBinding,
                    presenting: viewModel.pendingInvitation
                ) { _ in
                    Button("Accept") { viewModel.acceptInvitation() }
                    Button("Decline", role: .cancel) { viewModel.declineInvitation() }
                } message: { invite in
                    Text("\(invite.peerName) wants to battle.")
                }
                .alert(
                    "Error",
                    isPresented: errorBinding,
                    presenting: viewModel.errorMessage
                ) { _ in
                    Button("OK") { viewModel.dismissError() }
                } message: { message in
                    Text(message)
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

    var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { _ in }
        )
    }

    var discoveryView: some View {
        Group {
            if viewModel.discoveredPeers.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    if viewModel.phase == .connecting {
                        PixelSpinner()
                        Text("Connecting…")
                            .font(.pixel14)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Searching for nearby trainers…")
                            .font(.pixel14)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Nearby trainers", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.pixel12)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                        ForEach(viewModel.discoveredPeers) { peer in
                            Button {
                                viewModel.invite(peer)
                            } label: {
                                HStack {
                                    Label(peer.name, systemImage: "person.fill")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.secondary)
                                }
                                .font(.pixel14)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.cardBackground)
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.phase == .connecting)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Picker Sheet

/// Modal sheet for pokemon + move selection after connecting to a peer.
private struct MultiplayerPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Pokemon.id) private var allPokemon: [Pokemon]

    var viewModel: MultiplayerSetupViewModel
    @State private var selectedForMoves: Pokemon?

    var body: some View {
        NavigationStack {
            pokemonGrid
                .applyPokedexStyling(title: "Pick your pokemon", color: .darkGrey)
                .foregroundStyle(.white)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .navigationDestination(item: $selectedForMoves) { pokemon in
                    MultiplayerMovePickerView(viewModel: viewModel, pokemon: pokemon)
                }
        }
        .onChange(of: viewModel.phase) { _, newPhase in
            if newPhase == .launching {
                dismiss()
            }
        }
        .onChange(of: viewModel.errorMessage) { _, error in
            if error != nil { dismiss() }
        }
    }
}

// MARK: - Private
private extension MultiplayerPickerSheet {
    var pokemonGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(maximum: .infinity), spacing: 2),
                    GridItem(.flexible(maximum: .infinity), spacing: 2)
                ],
                spacing: 2
            ) {
                ForEach(allPokemon, id: \.id) { pokemon in
                    Button {
                        viewModel.selectPokemon(pokemon)
                        selectedForMoves = pokemon
                    } label: {
                        PokemonSpriteCard(pokemon: pokemon)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

}

// MARK: - Move Picker

/// Separate View struct so `@Observable` tracking works through
/// `navigationDestination`. Function-returned anonymous views don't
/// reliably re-evaluate `safeAreaBar` content when observed properties change.
private struct MultiplayerMovePickerView: View {
    var viewModel: MultiplayerSetupViewModel
    let pokemon: Pokemon

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                selectedSummary
                movePicker
            }
        }
        .safeAreaBar(edge: .bottom) { submitButton }
        .applyPokedexStyling(title: "Pick moves", color: .darkGrey)
        .foregroundStyle(.white)
    }
}

// MARK: - Private
private extension MultiplayerMovePickerView {
    var selectedSummary: some View {
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
            .padding(.horizontal)
            let spacing: CGFloat = 2
            let columns = [
                GridItem(.flexible(), spacing: spacing),
                GridItem(.flexible(), spacing: spacing)
            ]
            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(viewModel.movePool, id: \.name, content: moveCard)
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
        let remaining = viewModel.maxSelections - viewModel.selectedMoveNames.count
        return PrimaryCapsuleButton(
            icon: "bolt.fill",
            title: ready ? "Ready!" : "Pick \(remaining) more",
            isEnabled: ready,
            isLoading: viewModel.phase == .waitingForOpponent,
            action: viewModel.submitLoadout
        )
        .padding(.horizontal, 24)
    }
}
