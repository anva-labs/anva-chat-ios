import Foundation

final class MutableChatInterfaceStateView: MutablePostboxView {
    fileprivate let peerId: PeerId
    private let threadId: Int64?
    fileprivate var value: StoredPeerChatInterfaceState?
    
    init(postbox: PostboxImpl, peerId: PeerId, threadId: Int64?) {
        self.peerId = peerId
        self.threadId = threadId
        
        self.reload(postbox: postbox)
    }
    
    private func reload(postbox: PostboxImpl) {
        if let threadId = self.threadId {
            self.value = postbox.peerChatThreadInterfaceStateTable.get(PeerChatThreadId(peerId: self.peerId, threadId: threadId))
        } else {
            self.value = postbox.peerChatInterfaceStateTable.get(self.peerId)
        }
    }
    
    func replay(postbox: PostboxImpl, transaction: PostboxTransaction) -> Bool {
        var updated = false
        
        if transaction.currentUpdatedPeerChatListEmbeddedStates.contains(self.peerId) {
            let previousValue = self.value
            self.reload(postbox: postbox)
            if previousValue != self.value {
                updated = true
            }
        }
        
        return updated
    }

    func refreshDueToExternalTransaction(postbox: PostboxImpl) -> Bool {
        self.reload(postbox: postbox)
        
        return true
    }
    
    func immutableView() -> PostboxView {
        return ChatInterfaceStateView(self)
    }
}

public final class ChatInterfaceStateView: PostboxView {
    public let value: StoredPeerChatInterfaceState?
    
    init(_ view: MutableChatInterfaceStateView) {
        self.value = view.value
    }
}
