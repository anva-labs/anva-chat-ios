import Foundation
import Postbox
import SwiftSignalKit

extension BotUserInfo {
    public func shouldTrackAnvaHomeConversation(threadId: Int64?) -> Bool {
        if threadId == Message.newTopicThreadId {
            return false
        }
        // Telegram represents a forum bot's main conversation as a direct chat or General (topic 1).
        return !self.flags.contains(.hasForum) || (threadId != nil && threadId != 1)
    }
}

public struct AnvaBotThreadActivityEvent: Equatable {
    public let accountPeerId: EnginePeer.Id
    public let peerId: EnginePeer.Id
    public let threadId: Int64?
    public let timestamp: Int32

    public init(
        accountPeerId: EnginePeer.Id,
        peerId: EnginePeer.Id,
        threadId: Int64?,
        timestamp: Int32
    ) {
        self.accountPeerId = accountPeerId
        self.peerId = peerId
        self.threadId = threadId
        self.timestamp = timestamp
    }
}

public final class AnvaBotThreadActivityCenter {
    public static let shared = AnvaBotThreadActivityCenter()

    private let lock = NSLock()
    private var subscribers = Bag<(AnvaBotThreadActivityEvent) -> Void>()

    public init() {
    }

    public func publish(_ event: AnvaBotThreadActivityEvent) {
        self.lock.lock()
        let items = self.subscribers.copyItems()
        self.lock.unlock()

        for item in items {
            item(event)
        }
    }

    public func events(accountPeerId: EnginePeer.Id) -> Signal<AnvaBotThreadActivityEvent, NoError> {
        return Signal { [weak self] subscriber in
            guard let self else {
                subscriber.putCompletion()
                return EmptyDisposable
            }

            self.lock.lock()
            let index = self.subscribers.add { event in
                if event.accountPeerId == accountPeerId {
                    subscriber.putNext(event)
                }
            }
            self.lock.unlock()

            return ActionDisposable { [weak self] in
                guard let self else {
                    return
                }
                self.lock.lock()
                self.subscribers.remove(index)
                self.lock.unlock()
            }
        }
    }
}

public struct EngineBotThreadSummary: Equatable {
    public let data: MessageHistoryThreadData?
    public let topMessage: EngineMessage?
    public let timestamp: Int32

    public init(
        data: MessageHistoryThreadData?,
        topMessage: EngineMessage?,
        timestamp: Int32
    ) {
        self.data = data
        self.topMessage = topMessage
        self.timestamp = timestamp
    }
}
