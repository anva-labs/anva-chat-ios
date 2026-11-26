import Foundation
import UIKit
import Display
import TelegramPresentationData

enum AnvaListLayout {
    static func applySearchBar(_ searchBar: UISearchBar, theme: PresentationTheme, placeholder: String) {
        searchBar.tintColor = theme.list.itemAccentColor
        searchBar.barTintColor = theme.list.plainBackgroundColor
        searchBar.placeholder = placeholder
        searchBar.searchTextField.textColor = theme.list.itemPrimaryTextColor
        searchBar.searchTextField.backgroundColor = theme.rootController.navigationSearchBar.inputFillColor
    }

    static func layoutSearchAndTable(
        searchBar: UISearchBar,
        tableView: UITableView,
        layout: ContainerViewLayout,
        topY: CGFloat
    ) {
        let sideLeft = layout.safeInsets.left
        let sideRight = layout.safeInsets.right
        let contentWidth = max(0.0, layout.size.width - sideLeft - sideRight)
        let searchHeight: CGFloat = 52.0

        searchBar.frame = CGRect(
            x: sideLeft,
            y: topY,
            width: contentWidth,
            height: searchHeight
        )

        let tableY = topY + searchHeight
        let bottomInset = max(layout.insets(options: [.input]).bottom, layout.safeInsets.bottom)
        tableView.frame = CGRect(
            x: sideLeft,
            y: tableY,
            width: contentWidth,
            height: max(0.0, layout.size.height - tableY)
        )
        tableView.contentInset = UIEdgeInsets(top: 0.0, left: 0.0, bottom: bottomInset, right: 0.0)
        tableView.scrollIndicatorInsets = tableView.contentInset
    }
}

final class AnvaEmptyStateView: UIView {
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let actionButton = UIButton(type: .system)

    var onAction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.activityIndicator.hidesWhenStopped = true

        self.titleLabel.font = UIFont.systemFont(ofSize: 18.0, weight: .semibold)
        self.titleLabel.textAlignment = .center
        self.titleLabel.numberOfLines = 0

        self.bodyLabel.font = UIFont.systemFont(ofSize: 14.0, weight: .regular)
        self.bodyLabel.textAlignment = .center
        self.bodyLabel.numberOfLines = 0

        self.actionButton.titleLabel?.font = UIFont.systemFont(ofSize: 15.0, weight: .semibold)
        self.actionButton.layer.cornerRadius = 18.0
        self.actionButton.isHidden = true
        self.actionButton.addTarget(self, action: #selector(self.actionPressed), for: .touchUpInside)

        self.addSubview(self.activityIndicator)
        self.addSubview(self.titleLabel)
        self.addSubview(self.bodyLabel)
        self.addSubview(self.actionButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateTheme(_ theme: PresentationTheme) {
        self.titleLabel.textColor = theme.list.itemPrimaryTextColor
        self.bodyLabel.textColor = theme.list.itemSecondaryTextColor
        self.activityIndicator.color = theme.list.itemSecondaryTextColor
        self.actionButton.backgroundColor = theme.list.itemAccentColor
        self.actionButton.setTitleColor(theme.chatList.unreadBadgeActiveTextColor, for: .normal)
    }

    func configure(title: String?, body: String?, actionTitle: String? = nil, isLoading: Bool = false) {
        self.titleLabel.text = title
        self.bodyLabel.text = body

        if let actionTitle, !actionTitle.isEmpty {
            self.actionButton.setTitle(actionTitle, for: .normal)
            self.actionButton.isHidden = false
        } else {
            self.actionButton.isHidden = true
        }

        if isLoading {
            self.activityIndicator.startAnimating()
        } else {
            self.activityIndicator.stopAnimating()
        }

        self.setNeedsLayout()
    }

    @objc private func actionPressed() {
        self.onAction?()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let bounds = self.bounds
        let maxWidth = max(120.0, bounds.width - 56.0)
        let titleSize = self.titleLabel.sizeThatFits(CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
        let bodySize = self.bodyLabel.sizeThatFits(CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
        let rawButtonSize = self.actionButton.sizeThatFits(CGSize(width: maxWidth, height: 44.0))
        let buttonSize = CGSize(
            width: min(maxWidth, ceil(rawButtonSize.width) + 40.0),
            height: max(38.0, ceil(rawButtonSize.height) + 14.0)
        )

        let showLoading = self.activityIndicator.isAnimating
        let showBody = !(self.bodyLabel.text?.isEmpty ?? true)
        let showAction = !self.actionButton.isHidden

        var totalHeight = ceil(titleSize.height)
        if showLoading {
            totalHeight += 32.0
        }
        if showBody {
            totalHeight += 8.0 + ceil(bodySize.height)
        }
        if showAction {
            totalHeight += 20.0 + buttonSize.height
        }

        var cursorY = max(24.0, floor((bounds.height - totalHeight) * 0.36))
        if showLoading {
            self.activityIndicator.frame = CGRect(
                x: floor((bounds.width - 24.0) / 2.0),
                y: cursorY,
                width: 24.0,
                height: 24.0
            )
            cursorY += 32.0
        }

        self.titleLabel.frame = CGRect(
            x: floor((bounds.width - maxWidth) / 2.0),
            y: cursorY,
            width: maxWidth,
            height: ceil(titleSize.height)
        )
        cursorY += ceil(titleSize.height)

        if showBody {
            cursorY += 8.0
            self.bodyLabel.frame = CGRect(
                x: floor((bounds.width - maxWidth) / 2.0),
                y: cursorY,
                width: maxWidth,
                height: ceil(bodySize.height)
            )
            cursorY += ceil(bodySize.height)
        } else {
            self.bodyLabel.frame = .zero
        }

        if showAction {
            cursorY += 20.0
            self.actionButton.frame = CGRect(
                x: floor((bounds.width - buttonSize.width) / 2.0),
                y: cursorY,
                width: buttonSize.width,
                height: buttonSize.height
            )
        }
    }
}
