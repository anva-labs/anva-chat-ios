import Foundation
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import LocalizedPeerData
import AccountContext

public enum AnvaThreadPreviewFormatter {
    public static func cleanPreviewText(_ rawText: String) -> String {
        guard !rawText.isEmpty else {
            return ""
        }
        var text = rawText
        if text.contains("```") {
            let pattern = "```[\\s\\S]*?```"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: (text as NSString).length), withTemplate: " ")
            }
        }
        let markerSet = CharacterSet(charactersIn: "#*`>~")
        let strippedScalars = text.unicodeScalars.filter { !markerSet.contains($0) }
        let normalized = String(String.UnicodeScalarView(strippedScalars))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func formatPreview(
        message: EngineMessage?,
        accountPeerId: EnginePeer.Id,
        mediaFallback: (EngineMedia) -> String,
        youPrefix: (String) -> String,
        emptyFallback: String
    ) -> String {
        guard let message else {
            return emptyFallback
        }
        let cleanedText = AnvaThreadPreviewFormatter.cleanPreviewText(Self.messageText(message))
        let mediaText = message.engineMedia.lazy.map(mediaFallback).first(where: { !$0.isEmpty }) ?? ""
        let body: String
        if !cleanedText.isEmpty {
            if !mediaText.isEmpty {
                body = "\(mediaText) \(cleanedText)"
            } else {
                body = cleanedText
            }
        } else if !mediaText.isEmpty {
            body = mediaText
        } else {
            body = emptyFallback
        }

        if body == emptyFallback {
            return emptyFallback
        }
        if !message.effectivelyIncoming(accountPeerId) {
            return youPrefix(body)
        }
        return body
    }

    static func messageText(_ message: EngineMessage) -> String {
        if let richText = message.richText {
            let text = richReplyQuoteFlatText(instantPageQuotableNodes(richText.instantPage.blocks))
            if !text.isEmpty {
                return text
            }
        }
        return message.text
    }
}

public struct AnvaThreadListItem: Equatable {
    public let key: AnvaTrackedThread.Key
    public let peerId: EnginePeer.Id
    public let threadId: Int64?
    public let botPeer: EnginePeer?
    public let botName: String
    public let canRenameCloudTopic: Bool
    public let topicIconFileId: Int64?
    public let title: String
    public let previewText: String
    public let draft: EngineBotChatDraft?
    public let lastActivityTimestamp: Int32
    public let unreadCount: Int
    public let isPinned: Bool
    public let pinnedAt: Int32?
}

public struct AnvaThreadsSnapshot: Equatable {
    public let items: [AnvaThreadListItem]
    public let totalUnreadCount: Int
    public let isLoading: Bool
}

final class AnvaThreadsDataSource {
    struct MessageMatch {
        let key: AnvaTrackedThread.Key
        let message: EngineMessage
        let excerpt: String
    }

    struct MessageSearchPage {
        let state: SearchMessagesState
        let oldestIndex: EngineMessage.Index?
        // A nil value records a result that had no displayable excerpt.
        let matches: [EngineMessage.Id: MessageMatch?]
        let hasMore: Bool

        static func orderedMatches(in pages: [EnginePeer.Id: MessageSearchPage]) -> [MessageMatch] {
            // Any unrequested page may still contain matches older than its last returned message.
            // Keep those positions out of the list until every bot chat has searched that far.
            let boundary = pages.values.compactMap { $0.hasMore ? $0.oldestIndex : nil }.max()
            var seenIds = Set<EngineMessage.Id>()
            return pages.values.flatMap { $0.matches.values.compactMap { $0 } }
                .filter { match in
                    boundary.map { match.message.index >= $0 } ?? true
                }
                .sorted { $0.message.index > $1.message.index }
                .filter { seenIds.insert($0.message.id).inserted }
        }
    }

    private let context: AccountContext
    private let store: AnvaThreadsStore
    private let fetchLock = NSLock()
    private var fetchedThreadKeys = Set<AnvaTrackedThread.Key>()

    init(context: AccountContext, store: AnvaThreadsStore) {
        self.context = context
        self.store = store
    }

    func searchMessages(query: String, visibleThreads: Set<AnvaTrackedThread.Key>, pages: [EnginePeer.Id: MessageSearchPage]) -> Signal<[EnginePeer.Id: MessageSearchPage], NoError> {
        let engine = self.context.engine.messages
        let batchSize = 8
        let peerIds = Set(visibleThreads.map(\.peerId))
        let remaining = Array(peerIds.filter { pages[$0]?.hasMore != false })
        var results: Signal<[EnginePeer.Id: MessageSearchPage], NoError> = .single(pages)
        for offset in stride(from: 0, to: remaining.count, by: batchSize) {
            let batch = remaining[offset ..< min(offset + batchSize, remaining.count)]
            let searches = batch.map { peerId -> Signal<(EnginePeer.Id, MessageSearchPage), NoError> in
                let previous = pages[peerId]
                let location = SearchMessagesLocation.peer(peerId: peerId, fromId: nil, tags: nil, reactions: nil, threadId: nil, minDate: nil, maxDate: nil)
                return engine.searchMessages(location: location, query: query, state: previous?.state, limit: 20)
                |> map { result, state in
                    var matches: [EngineMessage.Id: MessageMatch?] = [:]
                    for message in result.messages {
                        let key = AnvaTrackedThread.Key(peerId: message.id.peerId, threadId: message.threadId)
                        guard key.peerId == peerId, visibleThreads.contains(key) else {
                            continue
                        }
                        if let previousMatch = previous?.matches[message.id] {
                            matches.updateValue(previousMatch, forKey: message.id)
                            continue
                        }
                        let message = EngineMessage(message)
                        let excerpt = Self.searchExcerpt(in: AnvaThreadPreviewFormatter.messageText(message), query: query)
                        matches.updateValue(excerpt.isEmpty ? nil : MessageMatch(key: key, message: message, excerpt: excerpt), forKey: message.id)
                    }
                    let oldestIndex = result.messages.last?.index
                    return (peerId, MessageSearchPage(
                        state: state,
                        oldestIndex: oldestIndex,
                        matches: matches,
                        hasMore: !result.completed && oldestIndex != nil && oldestIndex != previous?.oldestIndex
                    ))
                }
            }
            results = results |> mapToSignal { previous in
                return combineLatest(searches) |> map { updates in
                    var pages = previous
                    for (peerId, page) in updates {
                        pages[peerId] = page
                    }
                    return pages
                }
            }
        }
        return results
    }

    private static func searchExcerpt(in text: String, query: String) -> String {
        let text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let match = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive])
            ?? query.split(whereSeparator: \.isWhitespace).lazy.compactMap { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) }.first
        let start = match.map { text.index($0.lowerBound, offsetBy: -24, limitedBy: text.startIndex) ?? text.startIndex } ?? text.startIndex
        let end = text.index(start, offsetBy: 140, limitedBy: text.endIndex) ?? text.endIndex
        return (start == text.startIndex ? "" : "…") + text[start ..< end] + (end == text.endIndex ? "" : "…")
    }

    func snapshotSignal() -> Signal<AnvaThreadsSnapshot, NoError> {
        let context = self.context
        let accountPeerId = context.account.peerId

        return combineLatest(
            self.store.threadState,
            context.engine.messages.botForumChatListPeerIds(),
            context.sharedContext.presentationData
        )
        |> mapToSignal { [weak self] threadState, discovery, presentationData -> Signal<AnvaThreadsSnapshot, NoError> in
            let strings = AnvaStrings(strings: presentationData.strings)
            let localKeys = threadState.items.compactMap { $0.lastLocalSendAt != nil ? $0.key : nil }
            guard !localKeys.isEmpty || !discovery.peerIds.isEmpty else {
                return .single(AnvaThreadsSnapshot(items: [], totalUnreadCount: 0, isLoading: discovery.isLoading))
            }

            let uniquePeerIds = Set(localKeys.map(\.peerId)).union(discovery.peerIds)
            let forumPeerIds = Set(localKeys.compactMap { $0.threadId != nil ? $0.peerId : nil }).union(discovery.peerIds)
            let mainChatPeerIds = Array(Set(localKeys.compactMap { $0.threadId == nil ? $0.peerId : nil }))

            let peersSignal = context.engine.data.subscribe(
                EngineDataMap(uniquePeerIds.map { TelegramEngine.EngineData.Item.Peer.Peer(id: $0) })
            )

            let forumSummariesSignal = context.engine.messages.botThreadSummaries(peerIds: forumPeerIds)

            let mainTopMessagesSignal: Signal<[EnginePeer.Id: EngineMessage?], NoError>
            let mainReadCountersSignal: Signal<[EnginePeer.Id: EnginePeerReadCounters], NoError>
            if mainChatPeerIds.isEmpty {
                mainTopMessagesSignal = .single([:])
                mainReadCountersSignal = .single([:])
            } else {
                mainTopMessagesSignal = context.engine.data.subscribe(
                    EngineDataMap(mainChatPeerIds.map { TelegramEngine.EngineData.Item.Messages.TopMessage(id: $0) })
                )
                mainReadCountersSignal = context.engine.data.subscribe(
                    EngineDataMap(mainChatPeerIds.map { TelegramEngine.EngineData.Item.Messages.PeerReadCounters(id: $0) })
                )
            }

            return combineLatest(
                peersSignal,
                forumSummariesSignal,
                mainTopMessagesSignal,
                mainReadCountersSignal,
                context.engine.messages.botChatDrafts(conversations: localKeys.map { ($0.peerId, $0.threadId) })
            )
            |> map { peersMap, forum, mainTopMessages, mainReadCounters, drafts -> AnvaThreadsSnapshot in
                var syncedKeys = Set<AnvaTrackedThread.Key>()
                for (peerId, summaries) in forum.summaries where discovery.peerIds.contains(peerId) {
                    for threadId in summaries.keys where threadId > 1 && threadId != EngineMessage.newTopicThreadId {
                        syncedKeys.insert(AnvaTrackedThread.Key(peerId: peerId, threadId: threadId))
                    }
                }
                var listItems: [AnvaThreadListItem] = []
                var totalUnread = 0

                for tracked in threadState.visibleThreads(syncedKeys: syncedKeys) {
                    let peerId = tracked.key.peerId
                    let botPeer = peersMap[peerId] ?? nil
                    if case let .user(user) = botPeer, let botInfo = user.botInfo,
                       !botInfo.shouldTrackAnvaHomeConversation(threadId: tracked.key.threadId) {
                        continue
                    }

                    let botName: String
                    if let botPeer {
                        let display = botPeer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
                        botName = display.isEmpty ? strings.unknownBot : display
                    } else {
                        botName = strings.unknownBot
                    }

                    let canRenameCloudTopic: Bool
                    if let threadId = tracked.key.threadId,
                       threadId > 0,
                       case let .user(user) = botPeer,
                       let botInfo = user.botInfo,
                       botInfo.flags.contains(.hasForum),
                       botInfo.flags.contains(.forumManagedByUser) {
                        canRenameCloudTopic = true
                    } else {
                        canRenameCloudTopic = false
                    }

                    let topicData: MessageHistoryThreadData?
                    let topMessage: EngineMessage?
                    let activityTimestamp: Int32
                    let incomingUnreadCount: Int32
                    var draft = drafts[peerId]?[tracked.key.threadId]

                    if let threadId = tracked.key.threadId {
                        let summary = forum.summaries[peerId]?[threadId]
                        topicData = summary?.data
                        if topicData == nil {
                            self?.backfillThreadInfoIfNeeded(key: tracked.key)
                        }
                        topMessage = summary?.topMessage
                        activityTimestamp = summary?.timestamp ?? 0
                        incomingUnreadCount = topicData?.incomingUnreadCount ?? 0
                        if let summary {
                            draft = summary.draft
                        }
                    } else {
                        topicData = nil
                        topMessage = mainTopMessages[peerId] ?? nil
                        activityTimestamp = topMessage?.timestamp ?? 0
                        incomingUnreadCount = mainReadCounters[peerId]?.count ?? 0
                    }

                    let title: String
                    if let customTitle = tracked.customTitle, !customTitle.isEmpty {
                        title = customTitle
                    } else if let cloudTitle = topicData?.info.title, !cloudTitle.isEmpty {
                        title = cloudTitle
                    } else {
                        title = botName
                    }
                    let previewText = AnvaThreadPreviewFormatter.formatPreview(
                        message: topMessage,
                        accountPeerId: accountPeerId,
                        mediaFallback: { strings.mediaLabel(for: $0) },
                        youPrefix: { strings.youPrefix($0) },
                        emptyFallback: strings.noMessages
                    )
                    let lastActivityTimestamp = max(activityTimestamp, tracked.lastLocalSendAt ?? 0, tracked.addedAt)
                    let unreadCount = max(0, Int(incomingUnreadCount))
                    totalUnread += unreadCount
                    listItems.append(AnvaThreadListItem(
                        key: tracked.key,
                        peerId: peerId,
                        threadId: tracked.key.threadId,
                        botPeer: botPeer,
                        botName: botName,
                        canRenameCloudTopic: canRenameCloudTopic,
                        topicIconFileId: topicData?.info.icon,
                        title: title,
                        previewText: previewText,
                        draft: draft,
                        lastActivityTimestamp: lastActivityTimestamp,
                        unreadCount: unreadCount,
                        isPinned: tracked.isPinned,
                        pinnedAt: tracked.pinnedAt
                    ))
                }

                listItems.sort { lhs, rhs in
                    if lhs.isPinned != rhs.isPinned {
                        return lhs.isPinned && !rhs.isPinned
                    }
                    if lhs.isPinned && rhs.isPinned {
                        let lhsPin = lhs.pinnedAt ?? lhs.lastActivityTimestamp
                        let rhsPin = rhs.pinnedAt ?? rhs.lastActivityTimestamp
                        if lhsPin != rhsPin {
                            return lhsPin > rhsPin
                        }
                    }
                    if lhs.lastActivityTimestamp != rhs.lastActivityTimestamp {
                        return lhs.lastActivityTimestamp > rhs.lastActivityTimestamp
                    }
                    let lhsPeer = lhs.peerId.toInt64()
                    let rhsPeer = rhs.peerId.toInt64()
                    if lhsPeer != rhsPeer {
                        return lhsPeer < rhsPeer
                    }
                    return (lhs.threadId ?? -1) < (rhs.threadId ?? -1)
                }

                return AnvaThreadsSnapshot(items: listItems, totalUnreadCount: totalUnread, isLoading: discovery.isLoading || forum.isLoading)
            }
        }
        |> distinctUntilChanged
    }

    private func backfillThreadInfoIfNeeded(key: AnvaTrackedThread.Key) {
        guard let threadId = key.threadId, threadId > 0 else {
            return
        }
        self.fetchLock.lock()
        let inserted = self.fetchedThreadKeys.insert(key).inserted
        self.fetchLock.unlock()
        guard inserted else {
            return
        }
        let _ = self.context.engine.peers.fetchForumChannelTopic(id: key.peerId, threadId: threadId).startStandalone()
    }
}
