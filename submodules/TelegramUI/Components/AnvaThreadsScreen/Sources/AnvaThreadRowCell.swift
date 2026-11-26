import Foundation
import UIKit
import AsyncDisplayKit
import Display
import AvatarNode
import AccountContext
import TelegramCore
import TelegramPresentationData

final class AnvaThreadRowCell: UITableViewCell {
    static let reuseIdentifier = "AnvaThreadRowCell"
    static let rowHeight: CGFloat = 76.0

    private let avatarNode: AvatarNode
    private let pinImageView: UIImageView
    private let titleLabel: UILabel
    private let timeLabel: UILabel
    private let subtitleLabel: UILabel
    private let unreadBadgeView: UIView
    private let unreadBadgeLabel: UILabel
    private let separatorView: UIView

    private var hasPin = false
    private var unreadCount = 0

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        self.avatarNode = AvatarNode(font: avatarPlaceholderFont(size: 26.0))
        self.avatarNode.isLayerBacked = false

        let pinConfig = UIImage.SymbolConfiguration(pointSize: 13.0, weight: .medium)
        let pinImage = UIImage(systemName: "pin.fill", withConfiguration: pinConfig)?.withRenderingMode(.alwaysTemplate)
        self.pinImageView = UIImageView(image: pinImage)
        self.pinImageView.contentMode = .scaleAspectFit
        self.pinImageView.isHidden = true

        self.titleLabel = UILabel()
        self.titleLabel.font = Font.semibold(16.0)
        self.titleLabel.numberOfLines = 1
        self.titleLabel.lineBreakMode = .byTruncatingTail

        self.timeLabel = UILabel()
        self.timeLabel.font = Font.regular(14.0)
        self.timeLabel.numberOfLines = 1
        self.timeLabel.textAlignment = .right

        self.subtitleLabel = UILabel()
        self.subtitleLabel.font = Font.regular(15.0)
        self.subtitleLabel.numberOfLines = 2
        self.subtitleLabel.lineBreakMode = .byTruncatingTail

        self.unreadBadgeView = UIView()
        self.unreadBadgeView.layer.cornerRadius = 10.0
        self.unreadBadgeView.clipsToBounds = true
        self.unreadBadgeView.isHidden = true

        self.unreadBadgeLabel = UILabel()
        self.unreadBadgeLabel.font = Font.with(size: 12.0, design: .regular, weight: .semibold, traits: [.monospacedNumbers])
        self.unreadBadgeLabel.textAlignment = .center

        self.separatorView = UIView()

        super.init(style: style, reuseIdentifier: reuseIdentifier)

        self.contentView.addSubview(self.avatarNode.view)
        self.contentView.addSubview(self.titleLabel)
        self.contentView.addSubview(self.timeLabel)
        self.contentView.addSubview(self.subtitleLabel)
        self.contentView.addSubview(self.pinImageView)
        self.contentView.addSubview(self.unreadBadgeView)
        self.unreadBadgeView.addSubview(self.unreadBadgeLabel)
        self.contentView.addSubview(self.separatorView)

        let selectedBackground = UIView()
        self.selectedBackgroundView = selectedBackground
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        item: AnvaThreadListItem,
        context: AccountContext,
        theme: PresentationTheme,
        strings: AnvaStrings,
        messageMatch: AnvaThreadsDataSource.MessageMatch?,
        isLastRow: Bool
    ) {
        self.hasPin = messageMatch == nil && item.isPinned
        self.unreadCount = messageMatch == nil ? item.unreadCount : 0
        let rowBackground = self.hasPin ? theme.chatList.pinnedItemBackgroundColor : theme.chatList.backgroundColor
        self.backgroundColor = rowBackground
        self.contentView.backgroundColor = rowBackground
        self.selectedBackgroundView?.backgroundColor = theme.chatList.itemHighlightedBackgroundColor

        self.avatarNode.setPeer(
            context: context,
            theme: theme,
            peer: item.botPeer,
            displayDimensions: CGSize(width: 60.0, height: 60.0)
        )

        self.pinImageView.isHidden = !self.hasPin
        self.pinImageView.tintColor = theme.chatList.pinnedBadgeColor

        self.titleLabel.text = item.title
        self.titleLabel.textColor = theme.chatList.titleColor

        self.timeLabel.text = strings.formatTimestamp(messageMatch?.message.timestamp ?? item.lastActivityTimestamp)
        self.timeLabel.textColor = theme.chatList.dateTextColor

        self.subtitleLabel.textColor = theme.chatList.messageTextColor
        if let messageMatch {
            self.subtitleLabel.text = messageMatch.excerpt
        } else if let draft = item.draft {
            let text: String
            switch draft {
            case let .text(draftText):
                text = draftText.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            case let .media(mediaType):
                text = strings.draftMediaLabel(mediaType)
            }
            let subtitle = NSMutableAttributedString(
                string: text.isEmpty ? strings.draftLabel : strings.draftLabel + ": ",
                attributes: [.foregroundColor: theme.chatList.messageDraftTextColor]
            )
            subtitle.append(NSAttributedString(string: text, attributes: [.foregroundColor: theme.chatList.messageTextColor]))
            self.subtitleLabel.attributedText = subtitle
        } else {
            self.subtitleLabel.text = item.previewText
        }

        if self.unreadCount > 0 {
            self.unreadBadgeView.isHidden = false
            self.unreadBadgeView.backgroundColor = theme.chatList.unreadBadgeActiveBackgroundColor
            self.unreadBadgeLabel.textColor = theme.chatList.unreadBadgeActiveTextColor
            self.unreadBadgeLabel.text = "\(self.unreadCount)"
        } else {
            self.unreadBadgeView.isHidden = true
            self.unreadBadgeLabel.text = nil
        }

        self.separatorView.backgroundColor = theme.chatList.itemSeparatorColor
        self.separatorView.isHidden = isLastRow

        self.setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let bounds = self.contentView.bounds
        let safeLeft = self.safeAreaInsets.left
        let safeRight = self.safeAreaInsets.right
        let avatarLeftInset: CGFloat = safeLeft + 16.0
        let avatarSize: CGFloat = 60.0
        let avatarGap: CGFloat = 10.0

        self.avatarNode.frame = CGRect(
            x: avatarLeftInset,
            y: floor((bounds.height - avatarSize) / 2.0),
            width: avatarSize,
            height: avatarSize
        )

        let textLeading = avatarLeftInset + avatarSize + avatarGap
        let textTrailing = bounds.width - safeRight - 16.0
        let contentWidth = max(0.0, textTrailing - textLeading)

        let topRowY: CGFloat = 9.0
        let topRowHeight: CGFloat = 20.0
        let timeSize = self.timeLabel.sizeThatFits(CGSize(width: 100.0, height: topRowHeight))
        let timeWidth = ceil(timeSize.width)
        let timeX = max(textLeading, textTrailing - timeWidth)
        self.timeLabel.frame = CGRect(
            x: timeX,
            y: topRowY + floor((topRowHeight - timeSize.height) / 2.0),
            width: timeWidth,
            height: ceil(timeSize.height)
        )

        let titleMaxWidth = max(0.0, (timeX - 8.0) - textLeading)
        self.titleLabel.frame = CGRect(
            x: textLeading,
            y: topRowY,
            width: titleMaxWidth,
            height: topRowHeight
        )

        var accessoryTrailingX = textTrailing
        let accessoryCenterY: CGFloat = bounds.height - 20.0

        if self.unreadCount > 0 {
            let badgeTextSize = self.unreadBadgeLabel.sizeThatFits(CGSize(width: 80.0, height: 20.0))
            let badgeHeight: CGFloat = 20.0
            let badgeWidth = max(badgeHeight, ceil(badgeTextSize.width) + 12.0)
            let badgeX = max(textLeading, accessoryTrailingX - badgeWidth)
            self.unreadBadgeView.frame = CGRect(
                x: badgeX,
                y: floor(accessoryCenterY - badgeHeight / 2.0),
                width: badgeWidth,
                height: badgeHeight
            )
            self.unreadBadgeLabel.frame = self.unreadBadgeView.bounds
            accessoryTrailingX = badgeX - 6.0
        }

        if self.hasPin {
            let pinSize: CGFloat = 18.0
            let pinX = max(textLeading, accessoryTrailingX - pinSize)
            self.pinImageView.frame = CGRect(
                x: pinX,
                y: floor(accessoryCenterY - pinSize / 2.0),
                width: pinSize,
                height: pinSize
            )
            accessoryTrailingX = pinX - 6.0
        }

        let subtitleMaxWidth = (self.unreadCount > 0 || self.hasPin)
            ? max(0.0, (accessoryTrailingX - 2.0) - textLeading)
            : contentWidth
        let subtitleY: CGFloat = topRowY + topRowHeight + 2.0
        let maxSubtitleHeight = max(18.0, bounds.height - subtitleY - 8.0)
        let subtitleSize = self.subtitleLabel.sizeThatFits(CGSize(width: subtitleMaxWidth, height: maxSubtitleHeight))
        self.subtitleLabel.frame = CGRect(
            x: textLeading,
            y: subtitleY,
            width: subtitleMaxWidth,
            height: min(maxSubtitleHeight, ceil(subtitleSize.height))
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
