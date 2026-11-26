import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext

public struct AnvaTrackedThread: Codable, Equatable {
    public struct Key: Hashable, Codable {
        public var peerId: EnginePeer.Id
        public var threadId: Int64?

        public init(peerId: EnginePeer.Id, threadId: Int64?) {
            self.peerId = peerId
            self.threadId = threadId
        }
    }

    public var key: Key
    public var addedAt: Int32
    public var lastLocalSendAt: Int32
    public var isPinned: Bool
    public var pinnedAt: Int32?
    public var customTitle: String?

    public init(
        key: Key,
        addedAt: Int32,
        lastLocalSendAt: Int32,
        isPinned: Bool = false,
        pinnedAt: Int32? = nil,
        customTitle: String? = nil
    ) {
        self.key = key
        self.addedAt = addedAt
        self.lastLocalSendAt = lastLocalSendAt
        self.isPinned = isPinned
        self.pinnedAt = pinnedAt
        self.customTitle = customTitle
    }
}

public struct AnvaTrackedThreadState: Codable, Equatable {
    public var items: [AnvaTrackedThread]

    public init(items: [AnvaTrackedThread] = []) {
        self.items = items
    }

    @discardableResult
    public mutating func recordInteraction(peerId: EnginePeer.Id, threadId: Int64?, timestamp: Int32) -> Bool {
        let key = AnvaTrackedThread.Key(peerId: peerId, threadId: threadId)
        if let index = self.items.firstIndex(where: { $0.key == key }) {
            let nextTimestamp = max(self.items[index].lastLocalSendAt, timestamp)
            if self.items[index].lastLocalSendAt != nextTimestamp {
                self.items[index].lastLocalSendAt = nextTimestamp
                return true
            }
            return false
        }

        self.items.append(AnvaTrackedThread(
            key: key,
            addedAt: timestamp,
            lastLocalSendAt: timestamp,
            isPinned: false,
            pinnedAt: nil,
            customTitle: nil
        ))
        return true
    }

    @discardableResult
    public mutating func togglePin(key: AnvaTrackedThread.Key, timestamp: Int32) -> Bool {
        guard let index = self.items.firstIndex(where: { $0.key == key }) else {
            return false
        }
        let nextPinned = !self.items[index].isPinned
        self.items[index].isPinned = nextPinned
        self.items[index].pinnedAt = nextPinned ? timestamp : nil
        return true
    }

    @discardableResult
    public mutating func setCustomTitle(key: AnvaTrackedThread.Key, title: String?) -> Bool {
        guard let index = self.items.firstIndex(where: { $0.key == key }) else {
            return false
        }
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = (trimmed?.isEmpty ?? true) ? nil : trimmed
        if self.items[index].customTitle == normalized {
            return false
        }
        self.items[index].customTitle = normalized
        return true
    }

    @discardableResult
    public mutating func remove(key: AnvaTrackedThread.Key) -> Bool {
        let previousCount = self.items.count
        self.items.removeAll { $0.key == key }
        return self.items.count != previousCount
    }
}

public final class AnvaThreadsStore {
    private let accountPeerId: EnginePeer.Id
    private let fileURL: URL
    private let queue = Queue(name: "AnvaThreadsStore")
    private var state: AnvaTrackedThreadState
    private let threadsPromise: ValuePromise<[AnvaTrackedThread]>
    private var activityDisposable: Disposable?

    public var threads: Signal<[AnvaTrackedThread], NoError> {
        return self.threadsPromise.get()
    }

    public var currentThreads: [AnvaTrackedThread] {
        var items: [AnvaTrackedThread] = []
        self.queue.sync {
            items = self.state.items
        }
        return items
    }

    public init(
        accountPeerId: EnginePeer.Id,
        fileURL: URL,
        activityEvents: Signal<AnvaBotThreadActivityEvent, NoError>
    ) {
        self.accountPeerId = accountPeerId
        self.fileURL = fileURL
        let loaded = AnvaThreadsStore.loadState(from: fileURL)
        self.state = loaded
        self.threadsPromise = ValuePromise(loaded.items, ignoreRepeated: true)

        self.activityDisposable = activityEvents.startStrict(next: { [weak self] event in
            guard let self, event.accountPeerId == self.accountPeerId else {
                return
            }
            self.recordInteraction(peerId: event.peerId, threadId: event.threadId, timestamp: event.timestamp)
        })
    }

    public convenience init(accountPeerId: EnginePeer.Id, basePath: String) {
        let url = URL(fileURLWithPath: basePath, isDirectory: true).appendingPathComponent("anva-threads.json")
        self.init(
            accountPeerId: accountPeerId,
            fileURL: url,
            activityEvents: AnvaBotThreadActivityCenter.shared.events(accountPeerId: accountPeerId)
        )
    }

    deinit {
        self.activityDisposable?.dispose()
    }

    public func recordInteraction(peerId: EnginePeer.Id, threadId: Int64?, timestamp: Int32 = Int32(Date().timeIntervalSince1970)) {
        self.mutate { state in
            state.recordInteraction(peerId: peerId, threadId: threadId, timestamp: timestamp)
        }
    }

    public func togglePin(key: AnvaTrackedThread.Key, timestamp: Int32 = Int32(Date().timeIntervalSince1970)) {
        self.mutate { state in
            state.togglePin(key: key, timestamp: timestamp)
        }
    }

    public func setCustomTitle(key: AnvaTrackedThread.Key, title: String?) {
        self.mutate { state in
            state.setCustomTitle(key: key, title: title)
        }
    }

    public func remove(key: AnvaTrackedThread.Key) {
        self.mutate { state in
            state.remove(key: key)
        }
    }

    public func flushPendingWritesForTesting() {
        self.queue.sync {}
    }

    private func mutate(_ block: @escaping (inout AnvaTrackedThreadState) -> Bool) {
        // A subscriber can request another mutation while receiving an update.
        self.queue.justDispatch {
            guard block(&self.state) else {
                return
            }
            self.threadsPromise.set(self.state.items)
            AnvaThreadsStore.saveState(self.state, to: self.fileURL)
        }
    }

    private static func loadState(from url: URL) -> AnvaTrackedThreadState {
        guard let data = try? Data(contentsOf: url) else {
            return AnvaTrackedThreadState()
        }
        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode(AnvaTrackedThreadState.self, from: data) {
            return decoded
        }
        return AnvaTrackedThreadState()
    }

    private static func saveState(_ state: AnvaTrackedThreadState, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(state) else {
            return
        }
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        try? data.write(to: url, options: [.atomic])
    }
}

public final class AnvaThreadsStoreRegistry {
    public static let shared = AnvaThreadsStoreRegistry()

    private let lock = NSLock()
    private var stores: [EnginePeer.Id: AnvaThreadsStore] = [:]

    private init() {
    }

    public func store(for context: AccountContext) -> AnvaThreadsStore {
        let accountPeerId = context.account.peerId
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        if let existing = self.stores[accountPeerId] {
            return existing
        }
        let store = AnvaThreadsStore(accountPeerId: accountPeerId, basePath: context.account.basePath)
        self.stores[accountPeerId] = store
        return store
    }
}
