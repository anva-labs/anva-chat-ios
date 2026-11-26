import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import AccountContext
import TelegramCore
import TelegramPresentationData
import AvatarNode
import LocalizedPeerData

private final class AnvaBotPickerCell: UITableViewCell {
    static let reuseIdentifier = "AnvaBotPickerCell"
    static let rowHeight: CGFloat = 68.0

    private let avatarNode: AvatarNode
    private let nameLabel: UILabel
    private let subtitleLabel: UILabel
    private let separatorView: UIView

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        self.avatarNode = AvatarNode(font: avatarPlaceholderFont(size: 18.0))
        self.avatarNode.isLayerBacked = false

        self.nameLabel = UILabel()
        self.nameLabel.font = Font.semibold(16.0)
        self.nameLabel.numberOfLines = 1
        self.nameLabel.lineBreakMode = .byTruncatingTail

        self.subtitleLabel = UILabel()
        self.subtitleLabel.font = Font.regular(14.0)
        self.subtitleLabel.numberOfLines = 1
        self.subtitleLabel.lineBreakMode = .byTruncatingTail

        self.separatorView = UIView()

        super.init(style: style, reuseIdentifier: reuseIdentifier)

        self.contentView.addSubview(self.avatarNode.view)
        self.contentView.addSubview(self.nameLabel)
        self.contentView.addSubview(self.subtitleLabel)
        self.contentView.addSubview(self.separatorView)

        let selectedBackground = UIView()
        self.selectedBackgroundView = selectedBackground
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        peer: EnginePeer,
        context: AccountContext,
        presentationData: PresentationData,
        strings: AnvaStrings,
        isLastRow: Bool
    ) {
        let theme = presentationData.theme
        self.backgroundColor = theme.list.plainBackgroundColor
        self.contentView.backgroundColor = theme.list.plainBackgroundColor
        self.selectedBackgroundView?.backgroundColor = theme.list.itemHighlightedBackgroundColor

        self.avatarNode.setPeer(
            context: context,
            theme: theme,
            peer: peer,
            displayDimensions: CGSize(width: 48.0, height: 48.0)
        )

        let title = peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
        self.nameLabel.text = title.isEmpty ? strings.unknownBot : title
        self.nameLabel.textColor = theme.list.itemPrimaryTextColor

        if let username = peer.addressName, !username.isEmpty {
            self.subtitleLabel.text = "@\(username)"
        } else {
            self.subtitleLabel.text = strings.pickerBotSubtitle
        }
        self.subtitleLabel.textColor = theme.list.itemSecondaryTextColor

        self.separatorView.backgroundColor = theme.list.itemPlainSeparatorColor
        self.separatorView.isHidden = isLastRow

        self.setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let bounds = self.contentView.bounds
        let horizontalInset: CGFloat = 16.0
        let avatarSize: CGFloat = 48.0
        let gap: CGFloat = 12.0

        self.avatarNode.frame = CGRect(
            x: horizontalInset,
            y: floor((bounds.height - avatarSize) / 2.0),
            width: avatarSize,
            height: avatarSize
        )

        let textLeading = horizontalInset + avatarSize + gap
        let textTrailing = bounds.width - horizontalInset
        let contentWidth = max(0.0, textTrailing - textLeading)

        self.nameLabel.frame = CGRect(
            x: textLeading,
            y: 13.0,
            width: contentWidth,
            height: 21.0
        )

        self.subtitleLabel.frame = CGRect(
            x: textLeading,
            y: 36.0,
            width: contentWidth,
            height: 19.0
        )

        let separatorHeight = UIScreenPixel
        self.separatorView.frame = CGRect(
            x: textLeading,
            y: bounds.height - separatorHeight,
            width: max(0.0, bounds.width - textLeading),
            height: separatorHeight
        )
    }
}

final class AnvaBotPickerScreen: ViewController, UITableViewDataSource, UITableViewDelegate {
    enum Purpose {
        case newThread(filter: (EnginePeer) -> Bool, onSelect: (EnginePeer, AnvaBotPickerScreen) -> Void)
        case manage

        func title(strings: AnvaStrings) -> String {
            switch self {
            case .newThread:
                return strings.pickerTitle
            case .manage:
                return strings.botsTitle
            }
        }

        func emptyTitle(strings: AnvaStrings) -> String {
            switch self {
            case .newThread:
                return strings.pickerEmptyTitle
            case .manage:
                return strings.managedBotsEmptyTitle
            }
        }
    }

    private enum BotListState {
        case loading
        case loaded([EnginePeer])
        case failed
    }

    private let context: AccountContext
    private let purpose: Purpose

    private var presentationData: PresentationData
    private var presentationDataDisposable: Disposable?
    private var botsDisposable: Disposable?

    private var state: BotListState
    private var bots: [EnginePeer] {
        if case let .loaded(bots) = self.state {
            return bots
        }
        return []
    }

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyView = AnvaEmptyStateView()

    init(context: AccountContext, purpose: Purpose) {
        self.context = context
        self.purpose = purpose
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        switch purpose {
        case .newThread:
            self.state = .loaded([])
        case .manage:
            self.state = .loading
        }

        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))

        self.navigationPresentation = .modal
        self.statusBar.statusBarStyle = self.presentationData.theme.rootController.statusBarStyle.style

        let strings = AnvaStrings(strings: self.presentationData.strings)
        self.title = purpose.title(strings: strings)
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: strings.close,
            style: .plain,
            target: self,
            action: #selector(self.closePressed)
        )

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
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.presentationDataDisposable?.dispose()
        self.botsDisposable?.dispose()
    }

    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.backgroundColor = self.presentationData.theme.list.plainBackgroundColor

        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.separatorStyle = .none
        self.tableView.rowHeight = AnvaBotPickerCell.rowHeight
        self.tableView.register(AnvaBotPickerCell.self, forCellReuseIdentifier: AnvaBotPickerCell.reuseIdentifier)
        self.tableView.backgroundView = self.emptyView

        self.displayNode.view.addSubview(self.tableView)

        self.applyPresentationData()
        self.loadBots()
        self.displayNodeDidLoad()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        if self.isNodeLoaded {
            let sideLeft = layout.safeInsets.left
            let sideRight = layout.safeInsets.right
            let contentWidth = max(0.0, layout.size.width - sideLeft - sideRight)
            let topY = self.cleanNavigationHeight
            let bottomInset = max(layout.insets(options: [.input]).bottom, layout.safeInsets.bottom)

            self.tableView.frame = CGRect(
                x: sideLeft,
                y: topY,
                width: contentWidth,
                height: max(0.0, layout.size.height - topY)
            )
            self.tableView.contentInset = UIEdgeInsets(top: 0.0, left: 0.0, bottom: bottomInset, right: 0.0)
            self.tableView.scrollIndicatorInsets = self.tableView.contentInset
        }
    }

    private func applyPresentationData() {
        let theme = self.presentationData.theme
        let strings = AnvaStrings(strings: self.presentationData.strings)

        self.statusBar.statusBarStyle = theme.rootController.statusBarStyle.style
        self.navigationBar?.updatePresentationData(NavigationBarPresentationData(presentationData: self.presentationData), transition: .immediate)

        self.title = self.purpose.title(strings: strings)
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: strings.close,
            style: .plain,
            target: self,
            action: #selector(self.closePressed)
        )

        if self.isNodeLoaded {
            self.displayNode.backgroundColor = theme.list.plainBackgroundColor
            self.tableView.backgroundColor = theme.list.plainBackgroundColor
            self.emptyView.updateTheme(theme)
            self.reloadBots()
        }
    }

    private func loadBots() {
        let signal: Signal<BotListState, NoError>
        switch self.purpose {
        case let .newThread(filter, _):
            signal = self.localBots()
            |> map { .loaded($0.filter(filter)) }
        case .manage:
            let engine = self.context.engine
            signal = engine.peers.managedBotIds()
            |> mapToSignal { ids -> Signal<BotListState, NoError> in
                guard let ids else {
                    return .single(.failed)
                }
                guard !ids.isEmpty else {
                    return .single(.loaded([]))
                }
                return engine.data.subscribe(EngineDataList(ids.map(TelegramEngine.EngineData.Item.Peer.Peer.init(id:))))
                |> map { peers in
                    return .loaded(peers.compactMap { $0 })
                }
            }
        }
        self.botsDisposable = (signal
        |> deliverOnMainQueue).startStrict(next: { [weak self] state in
            self?.state = state
            self?.reloadBots()
        })
    }

    private func localBots() -> Signal<[EnginePeer], NoError> {
        return self.context.engine.messages.chatList(group: .root, count: 200)
        |> map { chatList -> [EnginePeer] in
            var seen = Set<EnginePeer.Id>()
            var bots: [EnginePeer] = []
            for item in chatList.items.reversed() {
                guard let peer = item.renderedPeer.peer else {
                    continue
                }
                if case let .user(user) = peer, user.botInfo != nil, seen.insert(peer.id).inserted {
                    bots.append(peer)
                }
            }
            return bots
        }
    }

    private func reloadBots() {
        let strings = AnvaStrings(strings: self.presentationData.strings)
        self.emptyView.isHidden = !self.bots.isEmpty
        switch self.state {
        case .loading:
            self.emptyView.configure(title: nil, body: nil, isLoading: true)
        case .loaded:
            self.emptyView.configure(title: self.purpose.emptyTitle(strings: strings), body: nil)
        case .failed:
            self.emptyView.configure(title: strings.managedBotsErrorTitle, body: nil)
        }
        self.tableView.reloadData()
    }

    @objc private func closePressed() {
        self.dismiss(animated: true)
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.bots.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: AnvaBotPickerCell.reuseIdentifier, for: indexPath) as? AnvaBotPickerCell else {
            return UITableViewCell()
        }
        let peer = self.bots[indexPath.row]
        let strings = AnvaStrings(strings: self.presentationData.strings)
        cell.configure(
            peer: peer,
            context: self.context,
            presentationData: self.presentationData,
            strings: strings,
            isLastRow: indexPath.row == self.bots.count - 1
        )
        return cell
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let peer = self.bots[indexPath.row]
        switch self.purpose {
        case let .newThread(_, onSelectBot):
            onSelectBot(peer, self)
        case .manage:
            if let navigationController = self.navigationController as? NavigationController,
               let profile = self.context.sharedContext.makePeerInfoController(
                   context: self.context,
                   updatedPresentationData: nil,
                   peer: peer,
                   mode: .generic,
                   avatarInitiallyExpanded: false,
                   fromChat: false,
                   requestsContext: nil
               ) {
                navigationController.pushViewController(profile)
            }
        }
    }
}
