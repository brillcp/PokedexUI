import Foundation
import MultipeerConnectivity
import SwiftUI

/// Connection lifecycle status surfaced to the lobby UI.
enum MultipeerConnectionState: Equatable {
    case idle
    case hosting
    case browsing
    case connecting(to: String)
    case connected(peerName: String)
    case failed(String)
}

/// Inbound invitation a host has sent to a browsing guest, awaiting user
/// decision via `acceptInvitation` / `declineInvitation`.
struct PendingInvitation: Identifiable, Equatable {
    let id = UUID()
    let peerName: String
    fileprivate let handler: (Bool) -> Void

    static func == (lhs: PendingInvitation, rhs: PendingInvitation) -> Bool {
        lhs.id == rhs.id
    }
}

/// Role this device plays in the session. Advertiser = `.host`, browser =
/// `.guest`. Decided at the moment a peer chooses to host or browse.
enum MultipeerRole: Sendable {
    case host
    case guest
}

/// Process-wide MultipeerConnectivity wrapper. Owns the `MCSession`,
/// advertiser, and browser; surfaces discovered peers, connection state,
/// and an `AsyncStream` of typed `BattleMessage` payloads to consumers.
@MainActor
@Observable
final class MultipeerService: NSObject {
    private static let serviceType = "pokedex-vs"

    let messages: AsyncStream<BattleMessage>
    private let messageContinuation: AsyncStream<BattleMessage>.Continuation
    private let myPeerID: MCPeerID
    private let session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    private(set) var role: MultipeerRole?
    private(set) var connectionState: MultipeerConnectionState = .idle
    private(set) var discoveredPeers: [MCPeerID] = []
    private(set) var connectedPeers: [MCPeerID] = []
    private(set) var pendingInvitation: PendingInvitation?
    var localDisplayName: String { myPeerID.displayName }

    override init() {
        let name = UIDevice.current.name
        self.myPeerID = MCPeerID(displayName: name.isEmpty ? "Trainer" : name)
        self.session = MCSession(
            peer: myPeerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        var continuation: AsyncStream<BattleMessage>.Continuation!
        self.messages = AsyncStream { continuation = $0 }
        self.messageContinuation = continuation
        super.init()
        self.session.delegate = self
    }

    /// Begin advertising this device as a host. Disables any prior browse
    /// session so a peer can only play one role at a time.
    func startHosting() {
        stopBrowsing()
        role = .host
        advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: nil,
            serviceType: Self.serviceType
        )
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
        connectionState = .hosting
    }

    /// Begin browsing for nearby hosts. Disables advertising for the same
    /// reason `startHosting` disables browsing.
    func startBrowsing() {
        stopHosting()
        role = .guest
        discoveredPeers = []
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
        connectionState = .browsing
    }

    /// Stop advertising. Safe to call when not hosting.
    func stopHosting() {
        advertiser?.stopAdvertisingPeer()
        advertiser?.delegate = nil
        advertiser = nil
    }

    /// Stop browsing. Safe to call when not browsing.
    func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser?.delegate = nil
        browser = nil
        discoveredPeers = []
    }

    /// Browser-side: send an invite to a discovered host.
    func invite(_ peer: MCPeerID) {
        guard let browser else { return }
        connectionState = .connecting(to: peer.displayName)
        browser.invitePeer(peer, to: session, withContext: nil, timeout: 30)
    }

    /// Host-side: accept the latest pending invitation prompt.
    func acceptInvitation() {
        pendingInvitation?.handler(true)
        pendingInvitation = nil
    }

    /// Host-side: decline the latest pending invitation prompt.
    func declineInvitation() {
        pendingInvitation?.handler(false)
        pendingInvitation = nil
    }

    /// Send a typed message to all connected peers. Encoding or transport
    /// failures are logged but not thrown; the receive stream's `.disconnect`
    /// path covers loss-of-peer recovery.
    func send(_ message: BattleMessage) {
        guard !session.connectedPeers.isEmpty else { return }
        do {
            let data = try JSONEncoder().encode(message)
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            #if DEBUG
            print("MultipeerService.send error: \(error)")
            #endif
        }
    }

    /// Tear down the session and all discovery. Idempotent.
    func disconnect() {
        send(.disconnect)
        stopHosting()
        stopBrowsing()
        session.disconnect()
        role = nil
        connectedPeers = []
        connectionState = .idle
    }
}

// MARK: - MCSessionDelegate
extension MultipeerService: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                self.connectedPeers = session.connectedPeers
                self.connectionState = .connected(peerName: peerID.displayName)
                if self.role == .host { self.stopHosting() }
                if self.role == .guest { self.stopBrowsing() }
            case .connecting:
                self.connectionState = .connecting(to: peerID.displayName)
            case .notConnected:
                self.connectedPeers = session.connectedPeers
                if self.connectedPeers.isEmpty {
                    self.connectionState = .idle
                }
            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? JSONDecoder().decode(BattleMessage.self, from: data) else {
            #if DEBUG
            print("MultipeerService: dropped undecodable payload (\(data.count) bytes)")
            #endif
            return
        }
        Task { @MainActor in
            self.messageContinuation.yield(message)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension MultipeerService: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        let session = self.session
        Task { @MainActor in
            self.pendingInvitation = PendingInvitation(peerName: peerID.displayName) { accepted in
                invitationHandler(accepted, accepted ? session : nil)
            }
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in
            self.connectionState = .failed(error.localizedDescription)
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension MultipeerService: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            if !self.discoveredPeers.contains(peerID) {
                self.discoveredPeers.append(peerID)
            }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.discoveredPeers.removeAll { $0 == peerID }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            self.connectionState = .failed(error.localizedDescription)
        }
    }
}
