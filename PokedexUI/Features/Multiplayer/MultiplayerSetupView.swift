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
                .applyPokedexStyling(title: "Gym")
                .foregroundStyle(.white)
                .task { viewModel.startListening() }
                .onAppear(perform: viewModel.startDiscovery)
                .onDisappear(perform: viewModel.stopDiscovery)
                .animation(.default, value: viewModel.phase)
                .onChange(of: viewModel.isConnected) { _, connected in
                    if connected {
                        viewModel.showPicker = true
                    } else if viewModel.phase != .discovering {
                        viewModel.connectionLost()
                    }
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
                    if let old, new == nil, viewModel.phase == .launching {
                        viewModel.returnToLobby(battleEnded: old.viewModel.winner != nil)
                    }
                }
                .alert(
                    "Battle challange!",
                    isPresented: pendingInvitationBinding,
                    presenting: viewModel.pendingInvitation
                ) { _ in
                    Button("Accept", role: .confirm, action: viewModel.acceptInvitation)
                    Button("Decline", role: .cancel, action: viewModel.declineInvitation)
                } message: { invite in
                    Text("\(invite.peerName) wants to challange you to a 1v1 battle.")
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
                            .frame(maxWidth: .infinity)
                        } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .resizable()
                            .frame(width: 24, height: 24)
                        Text("No nearby trainers")
                    }
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .font(.pixel14)
                .frame(maxWidth: .infinity)
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
                    .padding(.vertical)
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
    @State private var searchText = ""
    @State private var selectedForMoves: Pokemon?

    var body: some View {
        NavigationStack {
            pokemonGrid
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
                .applyPokedexStyling(title: "Pick your fighter", color: .darkGrey)
                .foregroundStyle(.white)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .cancel) { dismiss() }
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
    var filteredPokemon: [Pokemon] {
        guard !searchText.isEmpty else { return allPokemon }
        let query = searchText.lowercased()
        return allPokemon.filter { $0.name.lowercased().contains(query) }
    }

    var pokemonGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(maximum: .infinity), spacing: 2),
                    GridItem(.flexible(maximum: .infinity), spacing: 2),
                    GridItem(.flexible(maximum: .infinity), spacing: 2)
                ],
                spacing: 2
            ) {
                ForEach(filteredPokemon, id: \.id) { pokemon in
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
        let waiting = viewModel.phase == .waitingForOpponent
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                selectedSummary
                movePicker
            }
        }
        .disabled(waiting)
        .opacity(waiting ? Opacity.disabled : 1)
        .animation(.easeInOut(duration: 0.2), value: waiting)
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
        MovePickerGrid(
            moves: viewModel.movePool,
            selectedNames: viewModel.selectedMoveNames,
            maxSelections: viewModel.maxSelections,
            onToggle: viewModel.toggleMove
        )
    }

    var submitButton: some View {
        let ready = viewModel.selectedPokemon != nil
            && viewModel.selectedMoveNames.count == viewModel.maxSelections
        let remaining = viewModel.maxSelections - viewModel.selectedMoveNames.count
        return PrimaryCapsuleButton(
            icon: "bolt.fill",
            title: ready ? "Ready" : "Pick \(remaining) more",
            loadingTitle: "Waiting for opponent",
            isEnabled: ready,
            isLoading: viewModel.phase == .waitingForOpponent,
            action: viewModel.submitLoadout
        )
        .padding(.horizontal, 24)
    }
}
