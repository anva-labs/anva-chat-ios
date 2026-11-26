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
        let cleanedText = AnvaThreadPreviewFormatter.cleanPreviewText(message.text)
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
    public let lastActivityTimestamp: Int32
    public let unreadCount: Int
    public let isPinned: Bool
    public let pinnedAt: Int32?
}

public struct AnvaThreadsSnapshot: Equatable {
    public let items: [AnvaThreadListItem]
    public let totalUnreadCount: Int
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

        static func orderedMatches(in pages: [AnvaTrackedThread.Key: MessageSearchPage]) -> [MessageMatch] {
            // Any unrequested page may still contain matches older than its last returned message.
            // Keep those positions out of the list until every conversation has searched that far.
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

    func searchMessages(query: String, conversations: [AnvaTrackedThread.Key], pages: [AnvaTrackedThread.Key: MessageSearchPage]) -> Signal<[AnvaTrackedThread.Key: MessageSearchPage], NoError> {
        let engine = self.context.engine.messages
        let batchSize = 8
        let remaining = conversations.filter { pages[$0]?.hasMore != false }
        var results: Signal<[AnvaTrackedThread.Key: MessageSearchPage], NoError> = .single(pages)
        for offset in stride(from: 0, to: remaining.count, by: batchSize) {
            let batch = remaining[offset ..< min(offset + batchSize, remaining.count)]
            let searches = batch.map { key -> Signal<(AnvaTrackedThread.Key, MessageSearchPage), NoError> in
                let previous = pages[key]
                let location = SearchMessagesLocation.peer(peerId: key.peerId, fromId: nil, tags: nil, reactions: nil, threadId: key.threadId, minDate: nil, maxDate: nil)
                return engine.searchMessages(location: location, query: query, state: previous?.state, limit: 20)
                |> map { result, state in
                    var matches: [EngineMessage.Id: MessageMatch?] = [:]
                    for message in result.messages {
                        guard message.id.peerId == key.peerId, message.threadId == nil || message.threadId == key.threadId else {
                            continue
                        }
                        if let previousMatch = previous?.matches[message.id] {
                            matches.updateValue(previousMatch, forKey: message.id)
                            continue
                        }
                        let message = EngineMessage(message)
                        let text = message.richText.map { richReplyQuoteFlatText(instantPageQuotableNodes($0.instantPage.blocks)) } ?? message.text
                        let excerpt = Self.searchExcerpt(in: text.isEmpty ? message.text : text, query: query)
                        matches.updateValue(excerpt.isEmpty ? nil : MessageMatch(key: key, message: message, excerpt: excerpt), forKey: message.id)
                    }
                    let oldestIndex = result.messages.last?.index
                    return (key, MessageSearchPage(
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
                    for (key, page) in updates {
                        pages[key] = page
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

        let trackedAndPresentation = combineLatest(
            self.store.threads,
            context.sharedContext.presentationData
        )

        return trackedAndPresentation
        |> mapToSignal { [weak self] trackedItems, presentationData -> Signal<AnvaThreadsSnapshot, NoError> in
            let strings = AnvaStrings(strings: presentationData.strings)
            guard !trackedItems.isEmpty else {
                return .single(AnvaThreadsSnapshot(items: [], totalUnreadCount: 0))
            }

            let uniquePeerIds = Array(Set(trackedItems.map(\.key.peerId)))
            let forumPeerIds = Set(trackedItems.compactMap { $0.key.threadId != nil ? $0.key.peerId : nil })
            let mainChatPeerIds = Array(Set(trackedItems.compactMap { $0.key.threadId == nil ? $0.key.peerId : nil }))

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
                mainReadCountersSignal
            )
            |> map { peersMap, forumSummaries, mainTopMessages, mainReadCounters -> AnvaThreadsSnapshot in
                var listItems: [AnvaThreadListItem] = []
                var totalUnread = 0

                for tracked in trackedItems {
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

                    if let threadId = tracked.key.threadId {
                        let summary = forumSummaries[peerId]?[threadId]
                        topicData = summary?.data
                        if topicData == nil {
                            self?.backfillThreadInfoIfNeeded(key: tracked.key)
                        }
                        topMessage = summary?.topMessage
                        activityTimestamp = summary?.timestamp ?? 0
                        incomingUnreadCount = topicData?.incomingUnreadCount ?? 0
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
                    let lastActivityTimestamp = max(activityTimestamp, tracked.lastLocalSendAt, tracked.addedAt)
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

                return AnvaThreadsSnapshot(items: listItems, totalUnreadCount: totalUnread)
            }
        }
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
