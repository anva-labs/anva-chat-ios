import Foundation
import UIKit
import AsyncDisplayKit
import Display
import AppBundle
import ComponentFlow
import ContextUI
import SwiftSignalKit
import AccountContext
import TelegramCore
import TelegramPresentationData
import SearchUI
import SearchBarNode
import ChatListHeaderComponent
import NavigationBarComponent
import SideColumnLayout

public final class AnvaThreadsScreen: ViewController, UITableViewDataSource, UITableViewDelegate {
    private let context: AccountContext
    private let store: AnvaThreadsStore
    private let dataSource: AnvaThreadsDataSource

    private var presentationData: PresentationData
    private var presentationDataDisposable: Disposable?
    private var snapshotDisposable: Disposable?
    private var openPeerDisposable = MetaDisposable()
    private var renameTopicDisposable = MetaDisposable()
    private let messageSearchDisposable = MetaDisposable()

    private var snapshot = AnvaThreadsSnapshot(items: [], totalUnreadCount: 0, isLoading: true)
    private var filteredItems: [AnvaThreadListItem] = []
    private var searchQuery: String = ""
    private var messageSearchRequest: (query: String, keys: Set<AnvaTrackedThread.Key>)?
    private var messageSearchPages: [AnvaTrackedThread.Key: AnvaThreadsDataSource.MessageSearchPage] = [:]
    private var messageMatches: [AnvaThreadsDataSource.MessageMatch] = []
    private var isLoadingMessageSearch = false

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyView = AnvaEmptyStateView()
    private let navigationBarView = ComponentView<Empty>()
    private var activeSearchBarNode: SearchBarNode?

    private var isSearchActive = false
    private var hasAppliedInitialScrollOffset = false
    private var currentLayout: ContainerViewLayout?
    private var currentNavigationBarHeight: CGFloat = 0.0

    public var configureOpenedChatController: ((ChatController) -> Void)?

    override public var navigationBarTransitionSource: NavigationBarTransitionSource? {
        if self.isNodeLoaded {
            return self.navigationBarView.view as? ChatListNavigationBar.View
        }
        return nil
    }

    public init(context: AccountContext) {
        self.context = context
        self.store = AnvaThreadsStoreRegistry.shared.store(for: context)
        self.dataSource = AnvaThreadsDataSource(context: context, store: self.store)
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }

        super.init(navigationBarPresentationData: nil)

        self.statusBar.statusBarStyle = self.presentationData.theme.rootController.statusBarStyle.style

        let strings = AnvaStrings(strings: self.presentationData.strings)
        self.title = strings.homeTitle
        self.tabBarItem.title = strings.homeTitle
        self.tabBarItemContextActionType = .always

        let icon = UIImage(bundleImageName: "Chat List/Tabs/IconNews")?.withRenderingMode(.alwaysTemplate)
        self.tabBarItem.image = icon
        self.tabBarItem.selectedImage = icon
        if !self.presentationData.reduceMotion {
            self.tabBarItem.animationName = "TabNews"
            self.tabBarItem.animationOffset = CGPoint(x: 0.0, y: UIScreenPixel)
        }

        self.scrollToTop = { [weak self] in
            guard let self, self.isNodeLoaded else {
                return
            }
            let topOffset = CGPoint(x: 0.0, y: -self.tableView.contentInset.top)
            self.tableView.setContentOffset(topOffset, animated: true)
        }

        self.presentationDataDisposable = (context.sharedContext.presentationData
        |> deliverOnMainQueue).startStrict(next: { [weak self] presentationData in
            guard let self else {
                return
            }
            if presentationData.theme !== self.presentationData.theme || presentationData.strings !== self.presentationData.strings {
                self.presentationData = presentationData
                self.applyPresentationData()
            }
        })

        self.snapshotDisposable = (self.dataSource.snapshotSignal()
        |> deliverOnMainQueue).startStrict(next: { [weak self] snapshot in
            guard let self else {
                return
            }
            self.snapshot = snapshot
            self.tabBarItem.badgeValue = snapshot.totalUnreadCount > 0 ? "\(snapshot.totalUnreadCount)" : nil
            self.applyFilterAndReload()
        })
    }

    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.presentationDataDisposable?.dispose()
        self.snapshotDisposable?.dispose()
        self.openPeerDisposable.dispose()
        self.renameTopicDisposable.dispose()
        self.messageSearchDisposable.dispose()
    }

    override public func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.backgroundColor = self.presentationData.theme.chatList.backgroundColor

        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.separatorStyle = .none
        self.tableView.rowHeight = AnvaThreadRowCell.rowHeight
        self.tableView.keyboardDismissMode = .onDrag
        self.tableView.contentInsetAdjustmentBehavior = .never
        self.tableView.scrollsToTop = false
        self.tableView.register(AnvaThreadRowCell.self, forCellReuseIdentifier: AnvaThreadRowCell.reuseIdentifier)

        self.emptyView.onAction = { [weak self] in
            self?.composePressed()
        }
        self.tableView.backgroundView = self.emptyView

        self.displayNode.view.addSubview(self.tableView)

        self.applyPresentationData()
        self.applyFilterAndReload()
        self.displayNodeDidLoad()
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.currentLayout = layout
        if self.isNodeLoaded {
            self.layoutSubviews(for: layout, transition: ComponentTransition(transition))
        }
    }

    private func layoutSubviews(for layout: ContainerViewLayout, transition: ComponentTransition) {
        let navigationBarHeight = self.updateNavigationBar(layout: layout, transition: transition)
        self.currentNavigationBarHeight = navigationBarHeight

        let previousTopInset = self.tableView.contentInset.top
        let wasAtTop = abs(self.tableView.contentOffset.y + previousTopInset) < 1.0

        let bottomInset = max(
            layout.insets(options: [.input]).bottom,
            max(layout.intrinsicInsets.bottom, layout.safeInsets.bottom)
        )
        let tableInsets = UIEdgeInsets(top: navigationBarHeight, left: 0.0, bottom: bottomInset, right: 0.0)

        transition.setFrame(view: self.tableView, frame: CGRect(origin: .zero, size: layout.size))
        self.tableView.contentInset = tableInsets
        self.tableView.scrollIndicatorInsets = tableInsets

        if !self.hasAppliedInitialScrollOffset || wasAtTop {
            self.hasAppliedInitialScrollOffset = true
            self.tableView.contentOffset = CGPoint(x: 0.0, y: -navigationBarHeight)
        }

        self.updateActiveSearchBarLayout(layout: layout, transition: transition.containedViewLayoutTransition)
        self.syncNavigationBarScroll(forceUpdate: true, transition: transition)
    }

    private func updateNavigationBar(layout: ContainerViewLayout, transition: ComponentTransition) -> CGFloat {
        let strings = AnvaStrings(strings: self.presentationData.strings)
        let leftButton = NavigationBarComponent.Button(
            id: "bots",
            content: .text(title: strings.botsTitle, isBold: false),
            action: { [weak self] _ in
                self?.openManagedBots()
            }
        )

        let composeButton = NavigationBarComponent.Button(
            id: "compose",
            content: .icon(imageName: "Chat List/ComposeIcon"),
            tint: .accent,
            action: { [weak self] _ in
                self?.composePressed()
            }
        )

        let headerContent = ChatListHeaderComponent.Content(
            title: strings.homeTitle,
            titleComponent: nil,
            chatListTitle: nil,
            leftButton: leftButton,
            rightButtons: [composeButton],
            backPressed: nil
        )

        let reservedBelow = (self.parent as? TabBarController)?.verticalTabBarFrame(for: layout)
        let sideColumn = sideColumnRegion(
            layout: layout,
            minY: (layout.statusBarHeight ?? 0.0) + 8.0,
            reservedBelow: reservedBelow
        )

        let navigationBarSize = self.navigationBarView.update(
            transition: transition,
            component: AnyComponent(ChatListNavigationBar(
                context: self.context,
                theme: self.presentationData.theme,
                strings: self.presentationData.strings,
                statusBarHeight: layout.navigationBarStatusBarHeight ?? 0.0,
                leftInset: layout.safeInsets.left,
                rightInset: layout.safeInsets.right,
                trailingButtonsInset: layout.navigationBarTrailingButtonsInset,
                search: ChatListNavigationBar.Search(
                    isEnabled: true,
                    placeholder: strings.searchPlaceholder
                ),
                activeSearch: self.isSearchActive ? ChatListNavigationBar.ActiveSearch(isExternal: false) : nil,
                primaryContent: headerContent,
                secondaryContent: nil,
                secondaryTransition: 0.0,
                storySubscriptions: nil,
                storiesIncludeHidden: false,
                uploadProgress: [:],
                headerPanels: nil,
                tabsNode: nil,
                tabsNodeIsSearch: false,
                accessoryPanelContainer: nil,
                accessoryPanelContainerHeight: 0.0,
                edgeEffectColor: self.presentationData.theme.chatList.backgroundColor,
                activateSearch: { [weak self] searchContentNode in
                    self?.activateSearch(searchContentNode: searchContentNode)
                },
                openStatusSetup: { _ in },
                allowAutomaticOrder: {},
                sideColumn: sideColumn
            )),
            environment: {},
            containerSize: layout.size
        )

        if let navigationBarComponentView = self.navigationBarView.view as? ChatListNavigationBar.View {
            if navigationBarComponentView.superview == nil {
                self.displayNode.view.addSubview(navigationBarComponentView)
            }
            if let activeSearchBarNode = self.activeSearchBarNode {
                self.displayNode.view.insertSubview(navigationBarComponentView, belowSubview: activeSearchBarNode.view)
            }
            transition.setFrame(view: navigationBarComponentView, frame: CGRect(origin: .zero, size: navigationBarSize))
            return navigationBarSize.height
        }
        return 0.0
    }

    private func updateActiveSearchBarLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        guard let searchBarNode = self.activeSearchBarNode else {
            return
        }
        let statusBarHeight = layout.navigationBarStatusBarHeight ?? 0.0
        let searchBarFrame = CGRect(
            x: 0.0,
            y: statusBarHeight + 8.0,
            width: layout.size.width,
            height: 44.0
        )
        transition.updateFrame(node: searchBarNode, frame: searchBarFrame)
        searchBarNode.updateLayout(
            boundingSize: searchBarFrame.size,
            leftInset: layout.safeInsets.left,
            rightInset: layout.safeInsets.right + layout.navigationBarTrailingButtonsInset,
            transition: transition
        )
    }

    private func syncNavigationBarScroll(forceUpdate: Bool, transition: ComponentTransition) {
        guard let navigationBarComponentView = self.navigationBarView.view as? ChatListNavigationBar.View else {
            return
        }
        let offset = self.isSearchActive ? 0.0 : (self.tableView.contentOffset.y + self.tableView.contentInset.top)
        navigationBarComponentView.applyScroll(
            offset: offset,
            allowAvatarsExpansion: false,
            forceUpdate: forceUpdate,
            transition: transition
        )
    }

    private func activateSearch(searchContentNode: NavigationBarSearchContentNode) {
        guard !self.isSearchActive, let layout = self.currentLayout else {
            return
        }
        self.isSearchActive = true
        let theme = self.presentationData.theme
        let strings = AnvaStrings(strings: self.presentationData.strings)

        let searchBarNode = SearchBarNode(
            theme: SearchBarNodeTheme(theme: theme, hasBackground: false, hasSeparator: false, inline: false),
            presentationTheme: theme,
            strings: self.presentationData.strings,
            fieldStyle: .glass,
            forceSeparator: false,
            displayBackground: false
        )
        searchBarNode.placeholderString = NSAttributedString(
            string: strings.searchPlaceholder,
            font: Font.regular(17.0),
            textColor: theme.rootController.navigationSearchBar.inputPlaceholderTextColor
        )
        searchBarNode.textUpdated = { [weak self] query, _ in
            guard let self else {
                return
            }
            self.searchQuery = query
            self.applyFilterAndReload()
        }
        searchBarNode.cancel = { [weak self] in
            self?.deactivateSearch(animated: true)
        }

        self.activeSearchBarNode = searchBarNode
        self.displayNode.view.addSubview(searchBarNode.view)
        self.updateActiveSearchBarLayout(layout: layout, transition: .immediate)

        let transition = ComponentTransition.easeInOut(duration: 0.3)
        self.layoutSubviews(for: layout, transition: transition)
        searchBarNode.animateIn(
            from: searchContentNode.placeholderNode,
            duration: 0.3,
            timingFunction: kCAMediaTimingFunctionSpring
        )
        searchBarNode.activate()
    }

    private func deactivateSearch(animated: Bool) {
        guard self.isSearchActive else {
            return
        }
        self.isSearchActive = false
        self.searchQuery = ""
        self.applyFilterAndReload()

        let searchBarNode = self.activeSearchBarNode
        self.activeSearchBarNode = nil
        searchBarNode?.deactivate(clear: true)

        let transition: ComponentTransition = animated ? .easeInOut(duration: 0.25) : .immediate
        if let layout = self.currentLayout {
            self.layoutSubviews(for: layout, transition: transition)
        }

        if let searchBarNode {
            if animated,
               let navigationBarComponentView = self.navigationBarView.view as? ChatListNavigationBar.View,
               let placeholderNode = navigationBarComponentView.searchContentNode?.placeholderNode {
                searchBarNode.transitionOut(
                    to: placeholderNode,
                    transition: transition.containedViewLayoutTransition,
                    completion: { [weak searchBarNode] in
                        searchBarNode?.view.removeFromSuperview()
                    }
                )
            } else {
                searchBarNode.view.removeFromSuperview()
            }
        }
    }

    private func applyPresentationData() {
        let theme = self.presentationData.theme
        let strings = AnvaStrings(strings: self.presentationData.strings)

        self.statusBar.statusBarStyle = theme.rootController.statusBarStyle.style
        self.title = strings.homeTitle
        self.tabBarItem.title = strings.homeTitle

        if self.isNodeLoaded {
            self.displayNode.backgroundColor = theme.chatList.backgroundColor
            self.tableView.backgroundColor = theme.chatList.backgroundColor
            self.emptyView.updateTheme(theme)

            if let activeSearchBarNode = self.activeSearchBarNode {
                activeSearchBarNode.updateThemeAndStrings(
                    theme: SearchBarNodeTheme(theme: theme, hasBackground: false, hasSeparator: false, inline: false),
                    presentationTheme: theme,
                    strings: self.presentationData.strings
                )
                activeSearchBarNode.placeholderString = NSAttributedString(
                    string: strings.searchPlaceholder,
                    font: Font.regular(17.0),
                    textColor: theme.rootController.navigationSearchBar.inputPlaceholderTextColor
                )
            }

            if let layout = self.currentLayout {
                self.layoutSubviews(for: layout, transition: .immediate)
            }
            self.applyFilterAndReload()
        }
    }

    private func applyFilterAndReload() {
        let query = self.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let foldedQuery = query.lowercased()
        if query.isEmpty {
            self.filteredItems = self.snapshot.items
        } else {
            self.filteredItems = self.snapshot.items.filter { item in
                item.title.lowercased().contains(foldedQuery) || item.botName.lowercased().contains(foldedQuery)
            }
        }

        self.updateMessageSearch(query: query)
        self.reloadRows()
    }

    private func updateMessageSearch(query: String) {
        let conversations = self.snapshot.items.map(\.key)
        let keys = Set(conversations)
        if query == self.messageSearchRequest?.query, keys == self.messageSearchRequest?.keys {
            return
        }

        self.messageSearchRequest = (query, keys)
        self.messageSearchDisposable.set(nil)
        self.messageSearchPages = [:]
        self.messageMatches = []
        self.isLoadingMessageSearch = false
        guard !query.isEmpty, !conversations.isEmpty else {
            self.activeSearchBarNode?.activity = false
            return
        }

        self.loadMessageSearchPage(query: query, conversations: conversations, debounce: true)
    }

    private func loadMessageSearchPage(query: String, conversations: [AnvaTrackedThread.Key], debounce: Bool) {
        let keys = Set(conversations)
        let pages = self.messageSearchPages
        self.isLoadingMessageSearch = true
        self.activeSearchBarNode?.activity = true
        let dataSource = self.dataSource
        let querySignal = Signal<String, NoError>.single(query)
        let scheduledQuery = debounce ? (querySignal |> delay(0.3, queue: .mainQueue())) : querySignal
        self.messageSearchDisposable.set((scheduledQuery
        |> mapToSignal { dataSource.searchMessages(query: $0, conversations: conversations, pages: pages) }
        |> deliverOnMainQueue).startStrict(next: { [weak self] pages in
            guard let self, self.messageSearchRequest?.query == query, self.messageSearchRequest?.keys == keys else {
                return
            }
            self.messageSearchPages = pages
            self.messageMatches = AnvaThreadsDataSource.MessageSearchPage.orderedMatches(in: pages)
            self.isLoadingMessageSearch = false
            self.activeSearchBarNode?.activity = false
            self.reloadRows()
            if self.isNodeLoaded {
                self.tableView.layoutIfNeeded()
                self.loadMoreMessageSearchIfNeeded()
            }
        }))
    }

    private func loadMoreMessageSearchIfNeeded() {
        guard self.isSearchActive, !self.isLoadingMessageSearch, let request = self.messageSearchRequest,
              self.messageSearchPages.values.contains(where: \.hasMore), !self.tableView.bounds.isEmpty else {
            return
        }
        let visibleBottom = self.tableView.contentOffset.y + self.tableView.bounds.height - self.tableView.contentInset.bottom
        if visibleBottom >= self.tableView.contentSize.height - AnvaThreadRowCell.rowHeight {
            self.loadMessageSearchPage(query: request.query, conversations: self.snapshot.items.map(\.key), debounce: false)
        }
    }

    private func reloadRows() {
        if self.isNodeLoaded {
            let strings = AnvaStrings(strings: self.presentationData.strings)
            if self.filteredItems.isEmpty, self.messageMatches.isEmpty, self.activeSearchBarNode?.activity != true {
                self.emptyView.isHidden = false
                if self.snapshot.items.isEmpty && self.snapshot.isLoading {
                    self.emptyView.configure(title: nil, body: nil, isLoading: true)
                } else if self.snapshot.items.isEmpty {
                    self.emptyView.configure(
                        title: strings.emptyTitle,
                        body: strings.emptyBody,
                        actionTitle: strings.emptyAction
                    )
                } else {
                    self.emptyView.configure(
                        title: strings.noResults,
                        body: nil,
                        actionTitle: nil
                    )
                }
            } else {
                self.emptyView.isHidden = true
            }
            self.tableView.reloadData()
        }
    }

    @objc private func composePressed() {
        self.openBotPicker()
    }

    override public func tabBarItemContextAction(sourceView: ContextExtractedContentContainingView, gesture: ContextGesture) {
        let strings = AnvaStrings(strings: self.presentationData.strings)
        let action = ContextMenuActionItem(text: strings.markAllAsRead, icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/ReadAll"), color: theme.contextMenu.primaryColor)
        }, action: { [weak self] _, dismiss in
            dismiss(.default)
            self?.markAllAsRead()
        })
        let controller = makeContextController(
            presentationData: self.presentationData,
            source: .reference(AnvaHomeTabMenuSource(view: sourceView.contentView)),
            items: .single(ContextController.Items(content: .list([.action(action)]))),
            gesture: gesture
        )
        self.context.sharedContext.mainWindow?.presentInGlobalOverlay(controller)
    }

    private func markAllAsRead() {
        var chatPeerIds: [EnginePeer.Id] = []
        var threadIdsByPeer: [EnginePeer.Id: [Int64]] = [:]
        for item in self.snapshot.items where item.unreadCount > 0 {
            if let threadId = item.threadId {
                threadIdsByPeer[item.peerId, default: []].append(threadId)
            } else if case let .user(user)? = item.botPeer, let botInfo = user.botInfo, !botInfo.flags.contains(.hasForum) {
                // Reading a forum by peer would affect topics outside Home.
                chatPeerIds.append(item.peerId)
            }
        }

        let messages = self.context.engine.messages
        if !chatPeerIds.isEmpty {
            let _ = messages.togglePeersUnreadMarkInteractively(peerIds: chatPeerIds, setToValue: false).startStandalone()
        }
        for (peerId, threadIds) in threadIdsByPeer {
            let _ = messages.markForumThreadsAsRead(peerId: peerId, threadIds: threadIds).startStandalone()
        }
    }

    public func openBotNewThread(botPeerId: EnginePeer.Id? = nil, sharedLink: URL? = nil, presentPhotoPreview: ((ChatController) -> Void)? = nil) {
        let textInputState = sharedLink.map {
            ChatTextInputState(inputText: NSAttributedString(string: "\($0.absoluteString)\n"))
        }
        if let botPeerId {
            self.openPeerDisposable.set((self.context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: botPeerId))
            |> deliverOnMainQueue).startStrict(next: { [weak self] peer in
                guard let self, let peer, self.isThreadModeBot(peer) else {
                    return
                }
                self.openNewThread(for: peer, replacingController: nil, textInputState: textInputState, presentPhotoPreview: presentPhotoPreview)
            }))
            return
        }

        let messages = self.context.engine.messages
        self.openPeerDisposable.set((combineLatest(
            self.dataSource.snapshotSignal() |> take(1),
            messages.chatList(group: .root, count: 200) |> take(1),
            messages.chatList(group: .archive, count: 200) |> take(1)
        )
        |> deliverOnMainQueue).startStrict(next: { [weak self] snapshot, rootChats, archivedChats in
            guard let self else {
                return
            }

            typealias BotActivity = (peer: EnginePeer, timestamp: Int32)
            let threadActivity = snapshot.items.compactMap { item -> BotActivity? in
                guard let peer = item.botPeer, self.isThreadModeBot(peer) else {
                    return nil
                }
                return (peer, item.lastActivityTimestamp)
            }
            let chatActivity = (rootChats.items + archivedChats.items).compactMap { item -> BotActivity? in
                guard let peer = item.renderedPeer.peer, self.isThreadModeBot(peer),
                      let timestamp = item.messages.map(\.timestamp).max() else {
                    return nil
                }
                return (peer, timestamp)
            }

            if let recent = (threadActivity + chatActivity).max(by: { $0.timestamp < $1.timestamp }) {
                self.openNewThread(for: recent.peer, replacingController: nil, textInputState: textInputState, presentPhotoPreview: presentPhotoPreview)
            } else {
                self.openBotPicker(textInputState: textInputState, presentPhotoPreview: presentPhotoPreview)
            }
        }))
    }

    private func isThreadModeBot(_ peer: EnginePeer) -> Bool {
        guard case let .user(user) = peer, let botInfo = user.botInfo else {
            return false
        }
        return botInfo.flags.contains(.hasForum) && botInfo.flags.contains(.forumManagedByUser)
    }

    private func resolveNavigationController() -> NavigationController? {
        if let navigationController = self.navigationController as? NavigationController {
            return navigationController
        }
        if let navigationController = self.parent?.navigationController as? NavigationController {
            return navigationController
        }
        return nil
    }

    private func openBotPicker(textInputState: ChatTextInputState? = nil, presentPhotoPreview: ((ChatController) -> Void)? = nil) {
        guard let navigationController = self.resolveNavigationController() else {
            return
        }
        let requiresThreadMode = textInputState != nil || presentPhotoPreview != nil
        let picker = AnvaBotPickerScreen(context: self.context, purpose: .newThread(filter: { [weak self] peer in
            return !requiresThreadMode || self?.isThreadModeBot(peer) == true
        }) { [weak self] peer, pickerController in
            self?.openNewThread(for: peer, replacingController: pickerController, textInputState: textInputState, presentPhotoPreview: presentPhotoPreview)
        })
        navigationController.pushViewController(picker)
    }

    private func openManagedBots() {
        guard let navigationController = self.resolveNavigationController() else {
            return
        }
        navigationController.pushViewController(AnvaBotPickerScreen(context: self.context, purpose: .manage))
    }

    private func openNewThread(for peer: EnginePeer, replacingController: ViewController?, textInputState: ChatTextInputState?, presentPhotoPreview: ((ChatController) -> Void)?) {
        guard let navigationController = self.resolveNavigationController() else {
            replacingController?.dismiss(animated: true)
            return
        }

        let chatLocation: NavigateToChatControllerParams.Location
        let useExisting: Bool
        if self.isThreadModeBot(peer) {
            chatLocation = .replyThread(ChatReplyThreadMessage(
                peerId: peer.id,
                threadId: EngineMessage.newTopicThreadId,
                channelMessageId: nil,
                isChannelPost: false,
                isForumPost: true,
                isMonoforumPost: false,
                maxMessage: nil,
                maxReadIncomingMessageId: nil,
                maxReadOutgoingMessageId: nil,
                unreadCount: 0,
                initialFilledHoles: IndexSet(),
                initialAnchor: .automatic,
                isNotAvailable: false
            ))
            useExisting = false
        } else {
            chatLocation = .peer(peer)
            useExisting = true
        }

        self.navigateToAnvaChat(
            navigationController: navigationController,
            chatLocation: chatLocation,
            textInputState: textInputState,
            activateInput: presentPhotoPreview == nil ? .text : nil,
            useExisting: useExisting,
            replacingController: replacingController,
            completion: { chat in presentPhotoPreview?(chat) }
        )
    }

    private func openThreadItem(_ item: AnvaThreadListItem, messageId: EngineMessage.Id? = nil) {
        guard let navigationController = self.resolveNavigationController() else {
            return
        }
        let subject = messageId.map { ChatControllerSubject.message(id: .id($0), highlight: .init(), timecode: nil, setupReply: false) }
        if let threadId = item.threadId {
            self.navigateToAnvaChat(
                navigationController: navigationController,
                chatLocation: .replyThread(ChatReplyThreadMessage(
                    peerId: item.peerId,
                    threadId: threadId,
                    channelMessageId: nil,
                    isChannelPost: false,
                    isForumPost: true,
                    isMonoforumPost: false,
                    maxMessage: nil,
                    maxReadIncomingMessageId: nil,
                    maxReadOutgoingMessageId: nil,
                    unreadCount: 0,
                    initialFilledHoles: IndexSet(),
                    initialAnchor: .automatic,
                    isNotAvailable: false
                )),
                subject: subject
            )
        } else if let peer = item.botPeer {
            self.navigateToAnvaChat(
                navigationController: navigationController,
                chatLocation: .peer(peer),
                subject: subject
            )
        } else {
            let context = self.context
            self.openPeerDisposable.set((context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: item.peerId))
            |> deliverOnMainQueue).startStrict(next: { [weak self, weak navigationController] peer in
                guard let self, let navigationController, let peer else {
                    return
                }
                self.navigateToAnvaChat(
                    navigationController: navigationController,
                    chatLocation: .peer(peer),
                    subject: subject
                )
            }))
        }
    }

    private func navigateToAnvaChat(
        navigationController: NavigationController,
        chatLocation: NavigateToChatControllerParams.Location,
        subject: ChatControllerSubject? = nil,
        textInputState: ChatTextInputState? = nil,
        activateInput: ChatControllerActivateInput? = nil,
        useExisting: Bool = true,
        replacingController: ViewController? = nil,
        completion: @escaping (ChatController) -> Void = { _ in }
    ) {
        self.context.sharedContext.navigateToChatController(NavigateToChatControllerParams(
            navigationController: navigationController,
            context: self.context,
            chatLocation: chatLocation,
            subject: subject,
            updateTextInputState: textInputState,
            activateInput: activateInput,
            keepStack: .always,
            useExisting: useExisting,
            animated: true,
            setupController: { [weak self] controller in
                self?.configureOpenedChatController?(controller)
            },
            pushController: { [weak self, weak navigationController, weak replacingController] controller, animated, pushCompletion in
                self?.configureOpenedChatController?(controller)
                if let replacingController, let navigationController {
                    let controllers = navigationController.viewControllers.filter { $0 !== replacingController }
                    navigationController.replaceControllersAndPush(
                        controllers: controllers,
                        controller: controller,
                        animated: animated,
                        completion: pushCompletion
                    )
                } else {
                    navigationController?.pushViewController(controller, animated: animated, completion: pushCompletion)
                }
            },
            completion: completion
        ))
    }

    private func presentRenameAlert(for item: AnvaThreadListItem) {
        let strings = AnvaStrings(strings: self.presentationData.strings)
        let alert = UIAlertController(title: strings.renameTitle, message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = strings.renamePlaceholder
            textField.text = item.title
            textField.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: strings.cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: strings.save, style: .default, handler: { [weak self, weak alert] _ in
            guard let self, let text = alert?.textFields?.first?.text else {
                return
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return
            }
            if item.canRenameCloudTopic, let threadId = item.threadId {
                self.renameTopicDisposable.set((self.context.engine.peers.editForumChannelTopic(
                    id: item.peerId,
                    threadId: threadId,
                    title: trimmed,
                    iconFileId: item.topicIconFileId
                )
                |> deliverOnMainQueue).startStrict(error: { [weak self] _ in
                    self?.store.setCustomTitle(key: item.key, title: trimmed)
                }, completed: { [weak self] in
                    self?.store.setCustomTitle(key: item.key, title: nil)
                }))
            } else {
                self.store.setCustomTitle(key: item.key, title: trimmed)
            }
        }))
        self.present(alert, animated: true)
    }

    // MARK: - UIScrollViewDelegate

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        self.syncNavigationBarScroll(forceUpdate: false, transition: .immediate)
        if scrollView.isDragging || scrollView.isDecelerating {
            self.loadMoreMessageSearchIfNeeded()
        }
    }

    public func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        guard !self.isSearchActive else {
            return
        }
        let topInset = scrollView.contentInset.top
        let targetRelativeOffset = targetContentOffset.pointee.y + topInset
        let searchHeight = ChatListNavigationBar.searchScrollHeight
        if targetRelativeOffset > 0.0 && targetRelativeOffset < searchHeight {
            let snappedRelativeOffset: CGFloat = targetRelativeOffset < searchHeight * 0.5 ? 0.0 : searchHeight
            targetContentOffset.pointee.y = snappedRelativeOffset - topInset
        }
    }

    // MARK: - UITableViewDataSource

    public func numberOfSections(in tableView: UITableView) -> Int {
        return self.messageMatches.isEmpty ? 1 : 2
    }

    public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return section == 1 ? AnvaStrings(strings: self.presentationData.strings).messageSearchResults : nil
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return section == 0 ? self.filteredItems.count : self.messageMatches.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: AnvaThreadRowCell.reuseIdentifier, for: indexPath) as? AnvaThreadRowCell else {
            return UITableViewCell()
        }
        let match = indexPath.section == 1 ? self.messageMatches[indexPath.row] : nil
        let item: AnvaThreadListItem
        if let match {
            guard let conversation = self.snapshot.items.first(where: { $0.key == match.key }) else {
                return UITableViewCell()
            }
            item = conversation
        } else {
            item = self.filteredItems[indexPath.row]
        }
        let strings = AnvaStrings(strings: self.presentationData.strings)
        cell.configure(
            item: item,
            context: self.context,
            theme: self.presentationData.theme,
            strings: strings,
            messageMatch: match,
            isLastRow: indexPath.row == self.tableView(tableView, numberOfRowsInSection: indexPath.section) - 1
        )
        return cell
    }

    public func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return indexPath.section == 0
    }

    public func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete, indexPath.section == 0, indexPath.row < self.filteredItems.count {
            let item = self.filteredItems[indexPath.row]
            self.store.remove(key: item.key)
        }
    }

    // MARK: - UITableViewDelegate

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if self.isSearchActive {
            self.activeSearchBarNode?.deactivate(clear: false)
        }
        if indexPath.section == 0 {
            self.openThreadItem(self.filteredItems[indexPath.row])
        } else {
            let match = self.messageMatches[indexPath.row]
            if let item = self.snapshot.items.first(where: { $0.key == match.key }) {
                self.openThreadItem(item, messageId: match.message.id)
            }
        }
    }

    public func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.section == 0 else {
            return nil
        }
        let item = self.filteredItems[indexPath.row]
        let strings = AnvaStrings(strings: self.presentationData.strings)

        let removeAction = UIContextualAction(style: .destructive, title: strings.remove) { [weak self] _, _, completion in
            self?.store.remove(key: item.key)
            completion(true)
        }
        removeAction.image = UIImage(systemName: "trash")

        let pinAction = UIContextualAction(style: .normal, title: item.isPinned ? strings.unpin : strings.pin) { [weak self] _, _, completion in
            self?.store.togglePin(key: item.key)
            completion(true)
        }
        pinAction.backgroundColor = self.presentationData.theme.list.itemAccentColor
        pinAction.image = UIImage(systemName: item.isPinned ? "pin.slash.fill" : "pin.fill")

        let configuration = UISwipeActionsConfiguration(actions: [removeAction, pinAction])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    public func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard indexPath.section == 0 else {
            return nil
        }
        let item = self.filteredItems[indexPath.row]
        let strings = AnvaStrings(strings: self.presentationData.strings)
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else {
                return UIMenu(children: [])
            }
            let pinAction = UIAction(
                title: item.isPinned ? strings.unpin : strings.pin,
                image: UIImage(systemName: item.isPinned ? "pin.slash" : "pin")
            ) { [weak self] _ in
                self?.store.togglePin(key: item.key)
            }
            let renameAction = UIAction(
                title: strings.rename,
                image: UIImage(systemName: "pencil")
            ) { [weak self] _ in
                self?.presentRenameAlert(for: item)
            }
            let removeAction = UIAction(
                title: strings.remove,
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.store.remove(key: item.key)
            }
            return UIMenu(children: [pinAction, renameAction, removeAction])
        }
    }
}

private final class AnvaHomeTabMenuSource: ContextReferenceContentSource {
    let keepInPlace = true
    private let view: UIView

    init(view: UIView) {
        self.view = view
    }

    func transitionInfo() -> ContextControllerReferenceViewInfo? {
        return ContextControllerReferenceViewInfo(referenceView: self.view, contentAreaInScreenSpace: mainWindowScreenBounds, actionsPosition: .top)
    }
}
