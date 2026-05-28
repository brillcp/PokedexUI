import Foundation
import MultipeerConnectivity
import SwiftUI

/// Connection lifecycle status surfaced to the lobby UI.
enum MultipeerConnectionState: Equatable {
    case idle
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
@Observable
final class MultipeerService: NSObject {
    private static let serviceType = "pokedex-vs"

    private var subscribers: [UUID: AsyncStream<BattleMessage>.Continuation] = [:]
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
        super.init()
        self.session.delegate = self
    }

    /// Return a new `AsyncStream` that receives all future messages. Each
    /// subscriber gets its own copy (broadcast). The stream auto-unregisters
    /// on termination so callers don't need to manually unsubscribe.
    func messages() -> AsyncStream<BattleMessage> {
        let id = UUID()
        return AsyncStream { continuation in
            self.subscribers[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.subscribers.removeValue(forKey: id)
                }
            }
        }
    }

    /// Advertise and browse simultaneously so both devices see each other
    /// immediately. Role is decided when a connection is established: the
    /// device that sent the invite becomes `.guest`, the one that accepted
    /// becomes `.host`.
    func startDiscovery() {
        stopDiscovery()
        discoveredPeers = []
        advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: nil,
            serviceType: Self.serviceType
        )
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
        connectionState = .browsing
    }

    /// Stop both advertising and browsing. Safe to call when neither is active.
    func stopDiscovery() {
        stopHosting()
        stopBrowsing()
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

    /// Send an invite to a discovered peer. The inviter becomes the guest.
    func invite(_ peer: MCPeerID) {
        guard let browser else { return }
        role = .guest
        connectionState = .connecting(to: peer.displayName)
        browser.invitePeer(peer, to: session, withContext: nil, timeout: 30)
    }

    /// Accept the latest pending invitation. The accepter becomes the host.
    func acceptInvitation() {
        role = .host
        pendingInvitation?.handler(true)
        pendingInvitation = nil
    }

    /// Decline the latest pending invitation.
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
        stopDiscovery()
        session.disconnect()
        role = nil
        connectedPeers = []
        connectionState = .idle
    }
}

// MARK: - MCSessionDelegate
extension MultipeerService: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            self.connectedPeers = session.connectedPeers
            self.connectionState = .connected(peerName: peerID.displayName)
            self.stopDiscovery()
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

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? JSONDecoder().decode(BattleMessage.self, from: data) else {
            #if DEBUG
            print("MultipeerService: dropped undecodable payload (\(data.count) bytes)")
            #endif
            return
        }
        for continuation in self.subscribers.values {
            continuation.yield(message)
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension MultipeerService: MCNearbyServiceAdvertiserDelegate {
    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        let session = self.session
        self.pendingInvitation = PendingInvitation(peerName: peerID.displayName) { accepted in
            invitationHandler(accepted, accepted ? session : nil)
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        self.connectionState = .failed(error.localizedDescription)
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension MultipeerService: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        if !discoveredPeers.contains(peerID) {
            discoveredPeers.append(peerID)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        discoveredPeers.removeAll { $0 == peerID }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        connectionState = .failed(error.localizedDescription)
    }
}
