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
    private var battleComplete: Bool = false
    private var peerChallenge: ChallengePayload?

    let maxSelections: Int = 4
    let multipeer: MultipeerService

    var phase: MultiplayerSetupPhase = .discovering
    var showPicker: Bool = false
    var errorMessage: String?
    var selectedPokemon: Pokemon?
    var movePool: [Move] = []
    var selectedMoveNames: Set<String> = []
    var selectionOrder: [String] = []
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

    func acceptInvitation() {
        multipeer.acceptInvitation()
        phase = .connecting
    }

    func declineInvitation() {
        multipeer.declineInvitation()
    }

    /// Called when the peer we invited declined (MC went idle while connecting).
    func inviteDeclined() {
        invitedPeer = nil
        phase = .discovering
        errorMessage = "Trainer declined the battle."
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
        if !battleComplete { errorMessage = "Connection lost." }
        showPicker = false
        reset()
        multipeer.startDiscovery()
    }

    /// Called when navigating back from a finished battle.
    func returnToLobby(battleEnded: Bool = false) {
        if battleEnded { battleComplete = true }
        multipeer.disconnect()
        reset()
        multipeer.startDiscovery()
    }

    func selectPokemon(_ pokemon: Pokemon) {
        selectedPokemon = pokemon
        movePool = Self.rankedByImpact(movesForPokemon(pokemon))
        selectedMoveNames = []
        selectionOrder = []
        phase = .picking
    }

    func toggleMove(_ move: Move) {
        if selectedMoveNames.contains(move.name) {
            selectedMoveNames.remove(move.name)
            selectionOrder.removeAll { $0 == move.name }
            return
        }
        guard selectedMoveNames.count < maxSelections else { return }
        selectedMoveNames.insert(move.name)
        selectionOrder.append(move.name)
    }

    func selectedMoves() -> [Move] {
        let byName = Dictionary(movePool.map { ($0.name, $0) }, uniquingKeysWith: { _, last in last })
        return selectionOrder.compactMap { byName[$0] }
    }

    /// Send the locally chosen loadout to the peer.
    func submitLoadout() {
        guard let pokemon = selectedPokemon,
              selectedMoveNames.count == maxSelections,
              let role = multipeer.role
        else { return }
        let payload = ChallengePayload(
            pokemon: PokemonSummary(pokemon: pokemon),
            moveNames: selectionOrder
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
            errorMessage = "Opponent declined the challenge."
            showPicker = false
            reset()
        case .disconnect:
            guard phase != .discovering else { return }
            if !battleComplete { errorMessage = "Opponent left." }
            showPicker = false
            reset()
            multipeer.startDiscovery()
        case .battleEnded:
            battleComplete = true
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
        let selfMoves = selectedMoves()
        let peerMoves = peerChallenge.moveNames.compactMap { PokeBattleKit.move(named: $0) }
        guard peerMoves.count == maxSelections else {
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
        movePool = []
        selectedMoveNames = []
        selectionOrder = []
        ownChallengeSent = false
        battleComplete = false
        peerChallenge = nil
        launch = nil
    }

    func movesForPokemon(_ pokemon: Pokemon) -> [Move] {
        let names = Set(pokemon.moveNames)
        return PokeBattleKit.allMoves.filter { names.contains($0.name) && $0.isBattleReady }
    }

    static func rankedByImpact(_ moves: [Move]) -> [Move] {
        moves.sorted { lhs, rhs in
            let lDamage = (lhs.power ?? 0) > 0
            let rDamage = (rhs.power ?? 0) > 0
            if lDamage != rDamage { return lDamage }
            let lp = lhs.power ?? 0
            let rp = rhs.power ?? 0
            if lp != rp { return lp > rp }
            return (lhs.accuracy ?? 100) > (rhs.accuracy ?? 100)
        }
    }
}

/// Identifiable wrapper around `MCPeerID` for stable use in SwiftUI lists.
struct PeerHandle: Identifiable, Hashable {
    let id: MCPeerID
    var name: String { id.displayName }
}
