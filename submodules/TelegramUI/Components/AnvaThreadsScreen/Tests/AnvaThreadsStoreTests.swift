import XCTest
import Foundation
import SwiftSignalKit
import TelegramCore
@testable import AnvaThreadsScreen

final class AnvaThreadsStoreTests: XCTestCase {
    private let accountId = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(100))
    private let botA = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(201))
    private let botB = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(202))

    func testStateRecordDeduplicationPinRenameAndRemove() {
        var state = AnvaTrackedThreadState()

        XCTAssertTrue(state.recordInteraction(peerId: self.botA, threadId: 10, timestamp: 1000))
        XCTAssertEqual(state.items.count, 1)
        XCTAssertEqual(state.items[0].addedAt, 1000)
        XCTAssertEqual(state.items[0].lastLocalSendAt, 1000)

        // Recording an older or equal timestamp for the same key is a no-op.
        XCTAssertFalse(state.recordInteraction(peerId: self.botA, threadId: 10, timestamp: 950))
        XCTAssertEqual(state.items.count, 1)

        // Recording a newer timestamp updates lastLocalSendAt while keeping addedAt.
        XCTAssertTrue(state.recordInteraction(peerId: self.botA, threadId: 10, timestamp: 1100))
        XCTAssertEqual(state.items.count, 1)
        XCTAssertEqual(state.items[0].addedAt, 1000)
        XCTAssertEqual(state.items[0].lastLocalSendAt, 1100)

        // Different thread of the same bot creates a separate item.
        XCTAssertTrue(state.recordInteraction(peerId: self.botA, threadId: 20, timestamp: 1200))
        // Regular non-forum bot chat (threadId == nil) creates a separate item.
        XCTAssertTrue(state.recordInteraction(peerId: self.botB, threadId: nil, timestamp: 1300))
        XCTAssertEqual(state.items.count, 3)

        let keyA10 = AnvaTrackedThread.Key(peerId: self.botA, threadId: 10)
        XCTAssertTrue(state.togglePin(key: keyA10, timestamp: 1400))
        XCTAssertTrue(state.items[0].isPinned)
        XCTAssertEqual(state.items[0].pinnedAt, 1400)

        XCTAssertTrue(state.setCustomTitle(key: keyA10, title: "  Refactor Plan  "))
        XCTAssertEqual(state.items[0].customTitle, "Refactor Plan")
        XCTAssertTrue(state.setCustomTitle(key: keyA10, title: "   "))
        XCTAssertNil(state.items[0].customTitle)

        XCTAssertTrue(state.remove(key: keyA10))
        XCTAssertEqual(state.items.count, 2)
        XCTAssertFalse(state.remove(key: keyA10))
    }

    func testStorePersistenceStartsEmptyAndTracksOnlyMatchingAccountEvents() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("anva-threads-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("anva-threads.json")
        let pipe = ValuePipe<AnvaBotThreadActivityEvent>()

        var store: AnvaThreadsStore? = AnvaThreadsStore(
            accountPeerId: self.accountId,
            fileURL: fileURL,
            activityEvents: pipe.signal()
        )
        XCTAssertEqual(store?.currentThreads, [])

        // Events for another account are ignored.
        let otherAccount = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(999))
        pipe.putNext(AnvaBotThreadActivityEvent(accountPeerId: otherAccount, peerId: self.botA, threadId: 5, timestamp: 200))
        XCTAssertEqual(store?.currentThreads, [])

        // Events for this account are recorded and persisted.
        pipe.putNext(AnvaBotThreadActivityEvent(accountPeerId: self.accountId, peerId: self.botA, threadId: 42, timestamp: 300))
        store?.togglePin(key: AnvaTrackedThread.Key(peerId: self.botA, threadId: 42), timestamp: 350)
        store?.flushPendingWritesForTesting()
        store = nil

        // Reloading from disk restores only the locally tracked items.
        let reloaded = AnvaThreadsStore(
            accountPeerId: self.accountId,
            fileURL: fileURL,
            activityEvents: .never()
        )
        XCTAssertEqual(reloaded.currentThreads.count, 1)
        XCTAssertEqual(reloaded.currentThreads.first?.key, AnvaTrackedThread.Key(peerId: self.botA, threadId: 42))
        XCTAssertEqual(reloaded.currentThreads.first?.isPinned, true)
    }

    func testPinningDuringActivityUpdatePersistsThePin() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("anva-threads.json")
        let events = ValuePipe<AnvaBotThreadActivityEvent>()
        let store = AnvaThreadsStore(accountPeerId: self.accountId, fileURL: fileURL, activityEvents: events.signal())
        let key = AnvaTrackedThread.Key(peerId: self.botA, threadId: 42)
        let pinned = self.expectation(description: "The updated thread is pinned")
        let subscription = store.threads.startStrict(next: { threads in
            guard let thread = threads.first(where: { $0.key == key }) else {
                return
            }
            if thread.isPinned {
                pinned.fulfill()
            } else {
                store.togglePin(key: key, timestamp: 350)
            }
        })
        defer { subscription.dispose() }

        events.putNext(AnvaBotThreadActivityEvent(accountPeerId: self.accountId, peerId: key.peerId, threadId: key.threadId, timestamp: 300))
        self.wait(for: [pinned], timeout: 5.0)
        store.flushPendingWritesForTesting()

        let reloaded = AnvaThreadsStore(accountPeerId: self.accountId, fileURL: fileURL, activityEvents: .never())
        XCTAssertEqual(reloaded.currentThreads.first(where: { $0.key == key })?.isPinned, true)
    }

    func testPreviewTextStripsMarkdownNoise() {
        let raw = "**Done.**\n- Keep threads separate\n```swift\nlet x = 1\n```\n`ok`"
        XCTAssertEqual(AnvaThreadPreviewFormatter.cleanPreviewText(raw), "Done. - Keep threads separate ok")
    }
}
