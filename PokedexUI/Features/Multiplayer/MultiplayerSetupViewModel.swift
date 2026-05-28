import Foundation
import MultipeerConnectivity
import PokeBattleKit
import SwiftUI

/// Discrete states the multiplayer lobby moves through.
enum MultiplayerSetupPhase: Equatable {
    case discovering
    case connecting
    case picking
    case waitingForOpponent
    case launching
}

/// Composite payload the lobby hands back to the navigation host once both
/// peers have exchanged challenges and the battle view model is wired up.
struct MultiplayerLaunch: Identifiable, Hashable {
    let id = UUID()
    let viewModel: MultiplayerBattleViewModel

    static func == (lhs: MultiplayerLaunch, rhs: MultiplayerLaunch) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Drives `MultiplayerSetupView`. Owns peer discovery, the local pokemon +
/// move selection, the wire handshake, and the assembly of the live battle
/// view model once both peers have submitted their loadouts.
@MainActor
@Observable
final class MultiplayerSetupViewModel {
    private let container: AppContainer
    private var listenTask: Task<Void, Never>?
    private var ownChallengeSent: Bool = false
    private var peerChallenge: ChallengePayload?
    private var connectedPeerName: String?
    private var receivedBattleEnded: Bool = false

    let multipeer: MultipeerService
    let selection = MoveSelection()

    var phase: MultiplayerSetupPhase = .discovering
    var showPicker: Bool = false
    var errorMessage: String?
    var selectedPokemon: Pokemon?
    var invitedPeer: PeerHandle?
    var launch: MultiplayerLaunch?

    init(container: AppContainer) {
        self.container = container
        self.multipeer = container.multipeerService
    }

    /// Begin listening for peer messages. Call once from the view's `.task`
    /// modifier so the listen loop is tied to view lifetime, not init.
    func startListening() {
        guard listenTask == nil else { return }
        let stream = multipeer.messages()
        listenTask = Task { [weak self] in
            for await message in stream {
                guard let self else { return }
                await self.handle(message)
            }
        }
    }
}

// MARK: - Lobby actions
extension MultiplayerSetupViewModel {
    /// Start advertising + browsing. Called when the versus tab appears.
    func startDiscovery() {
        guard phase == .discovering else { return }
        multipeer.startDiscovery()
    }

    /// Stop advertising + browsing. Called when the versus tab disappears.
    func stopDiscovery() {
        guard phase == .discovering else { return }
        multipeer.stopDiscovery()
    }

    func invite(_ peer: PeerHandle) {
        invitedPeer = peer
        multipeer.invite(peer.id)
        phase = .connecting
    }

    /// Called when MC reports a successful peer connection.
    func peerConnected() {
        connectedPeerName = multipeer.connectedPeers.first?.displayName
        receivedBattleEnded = false
        showPicker = true
    }

    func acceptInvitation() {
        multipeer.acceptInvitation()
        phase = .connecting
    }

    func declineInvitation() {
        multipeer.declineInvitation()
    }

    /// Called when the peer we invited declined (MC went idle while connecting).
    func inviteDeclined() {
        let name = invitedPeer?.name ?? "Trainer"
        invitedPeer = nil
        phase = .discovering
        errorMessage = "\(name) declined the battle."
        multipeer.startDiscovery()
    }

    /// Called when the picker sheet is dismissed without completing.
    func pickerDismissed() {
        guard phase != .launching, launch == nil else { return }
        multipeer.disconnect()
        resetSelection()
        phase = .discovering
        multipeer.startDiscovery()
    }

    func dismissError() {
        errorMessage = nil
        if phase == .discovering {
            multipeer.startDiscovery()
        }
    }

    /// Called when MC drops unexpectedly during picking, waiting, or battle.
    func connectionLost() {
        if !battleEnded {
            let name = connectedPeerName ?? "Opponent"
            errorMessage = "\(name) canceled."
        }
        showPicker = false
        reset()
        multipeer.startDiscovery()
    }

    /// Called when navigating back from a finished battle.
    func returnToLobby() {
        multipeer.disconnect()
        reset()
        multipeer.startDiscovery()
    }

    func selectPokemon(_ pokemon: Pokemon) {
        selectedPokemon = pokemon
        selection.load(for: pokemon)
        phase = .picking
    }

    /// Send the locally chosen loadout to the peer.
    func submitLoadout() {
        guard let pokemon = selectedPokemon,
              selection.isFull,
              let role = multipeer.role
        else { return }
        let payload = ChallengePayload(
            pokemon: PokemonSummary(pokemon: pokemon),
            moveNames: selection.selectionOrder
        )
        switch role {
        case .host:  multipeer.send(.challengeProposed(payload))
        case .guest: multipeer.send(.challengeAccepted(payload))
        }
        ownChallengeSent = true
        if peerChallenge != nil {
            phase = .launching
            tryLaunch()
        } else {
            phase = .waitingForOpponent
        }
    }

    var pendingInvitation: PendingInvitation? { multipeer.pendingInvitation }

    var connectionState: MultipeerConnectionState { multipeer.connectionState }

    var discoveredPeers: [PeerHandle] {
        multipeer.discoveredPeers.map(PeerHandle.init(id:))
    }

    var isConnected: Bool { !multipeer.connectedPeers.isEmpty }

    /// Derived from `.battleEnded` message or launch VM's winner.
    var battleEnded: Bool { receivedBattleEnded || launch?.viewModel.winner != nil }
}

// MARK: - Private
private extension MultiplayerSetupViewModel {
    func handle(_ message: BattleMessage) async {
        switch message {
        case .hello(let version, _, _):
            if version != MultipeerProtocol.version {
                errorMessage = "Opponent uses a different protocol version."
                multipeer.disconnect()
                showPicker = false
                reset()
            }
        case .challengeProposed(let payload), .challengeAccepted(let payload):
            peerChallenge = payload
            if ownChallengeSent {
                phase = .launching
                tryLaunch()
            }
        case .challengeDeclined:
            let name = connectedPeerName ?? "Opponent"
            errorMessage = "\(name) declined the challenge."
            showPicker = false
            reset()
        case .disconnect:
            guard phase != .discovering else { return }
            if !battleEnded {
                let name = connectedPeerName ?? "Opponent"
                errorMessage = "\(name) canceled."
            }
            showPicker = false
            reset()
            multipeer.startDiscovery()
        case .battleEnded:
            receivedBattleEnded = true
        case .moveCommitted, .roundResolved, .rematch:
            break
        }
    }

    func tryLaunch() {
        guard ownChallengeSent,
              let peerChallenge,
              let role = multipeer.role,
              let pokemon = selectedPokemon
        else { return }
        let selfMoves = selection.selectedMoves
        let peerMoves = peerChallenge.moveNames.compactMap { PokeBattleKit.move(named: $0) }
        guard peerMoves.count == selection.maxSelections else {
            errorMessage = "Opponent sent an invalid loadout."
            showPicker = false
            reset()
            return
        }
        showPicker = false
        let viewModel = MultiplayerBattleViewModel(
            role: role,
            selfSummary: PokemonSummary(pokemon: pokemon),
            selfMoves: selfMoves,
            peerSummary: peerChallenge.pokemon,
            peerMoves: peerMoves,
            multipeer: multipeer,
            container: container
        )
        launch = MultiplayerLaunch(viewModel: viewModel)
    }

    func reset() {
        invitedPeer = nil
        phase = .discovering
        resetSelection()
    }

    func resetSelection() {
        selectedPokemon = nil
        selection.load(ranked: [])
        ownChallengeSent = false
        peerChallenge = nil
        connectedPeerName = nil
        launch = nil
    }

}

/// Identifiable wrapper around `MCPeerID` for stable use in SwiftUI lists.
struct PeerHandle: Identifiable, Hashable {
    let id: MCPeerID
    var name: String { id.displayName }
}
