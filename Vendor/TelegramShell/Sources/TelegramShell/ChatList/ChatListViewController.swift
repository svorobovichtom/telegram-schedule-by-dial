import UIKit

/// Main chat list. Source: submodules/ChatListUI/Sources/Node/ChatListItem.swift
/// (60pt avatar at x 16, text from x 84, semibold 16 / regular 15 / regular 14, 20pt badge).
public final class ChatListViewController: UITableViewController {
    public private(set) var chats: [DemoChat]
    private let features: [ChatFeature]
    private var theme: Theme = .dayClassic

    public init(chats: [DemoChat], features: [ChatFeature] = []) {
        self.chats = chats
        self.features = features
        super.init(style: .plain)
        title = "Chats"
        // Icons: TelegramUI/Images.xcassets/Chat List/Tabs, ComposeIcon (PresentationResourcesRootController.navigationComposeIcon).
        tabBarItem = UITabBarItem(title: "Chats", image: Graphics.asset("TGTabIconChats"), tag: 2)
    }

    required init?(coder: NSCoder) { fatalError() }

    public override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Edit", style: .plain, target: nil, action: nil)
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: Graphics.asset("TGComposeIcon"), style: .plain, target: nil, action: nil)
        navigationItem.searchController = UISearchController()
        navigationItem.hidesSearchBarWhenScrolling = false
        tableView.register(ChatListCell.self, forCellReuseIdentifier: "chat")
        tableView.rowHeight = 76
        tableView.separatorStyle = .none // drawn by the cell: from x 84 to the edge, none above the first row
        applyTheme()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _: UITraitCollection) in self.applyTheme() }
    }

    private func applyTheme() {
        theme = Theme.current(for: traitCollection)
        tableView.backgroundColor = theme.listBackground
        tableView.reloadData()
    }

    public func openChat(at index: Int, animated: Bool) {
        let controller = ChatViewController(chat: chats[index], features: features)
        navigationController?.pushViewController(controller, animated: animated)
    }

    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { chats.count }

    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "chat", for: indexPath) as! ChatListCell
        cell.configure(chats[indexPath.row], theme: theme)
        return cell
    }

    public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        openChat(at: indexPath.row, animated: true)
    }
}

final class ChatListCell: UITableViewCell {
    private let avatar = AvatarView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let dateLabel = UILabel()
    private let badge = UILabel()
    private let checkView = UIImageView(image: Graphics.checkImage(partial: false))
    private let separator = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        messageLabel.font = .systemFont(ofSize: 15)
        messageLabel.numberOfLines = 2
        dateLabel.font = .systemFont(ofSize: 14)
        dateLabel.textAlignment = .right
        badge.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        badge.textAlignment = .center
        badge.clipsToBounds = true
        [avatar, titleLabel, messageLabel, dateLabel, badge, checkView, separator].forEach(contentView.addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(_ chat: DemoChat, theme: Theme) {
        avatar.peer = chat.peer
        titleLabel.text = chat.peer.name
        titleLabel.textColor = theme.listTitle
        let last = chat.messages.last
        if let author = last?.author {
            let text = NSMutableAttributedString(string: author + "\n", attributes: [.foregroundColor: theme.listTitle])
            text.append(NSAttributedString(string: last?.text ?? "", attributes: [.foregroundColor: theme.listText]))
            messageLabel.attributedText = text
        } else {
            messageLabel.attributedText = nil
            messageLabel.text = last?.text
            messageLabel.textColor = theme.listText
        }
        dateLabel.text = last.map { MessageView.timeFormatter.string(from: $0.date) }
        dateLabel.textColor = theme.listText
        checkView.tintColor = theme.listCheck
        separator.backgroundColor = theme.listSeparator
        checkView.isHidden = last?.isOutgoing != true
        badge.isHidden = chat.unreadCount == 0
        badge.text = "\(chat.unreadCount)"
        badge.textColor = theme.badgeText
        badge.backgroundColor = chat.isMuted ? theme.badgeMutedFill : theme.badgeFill
        backgroundColor = chat.isPinned ? theme.pinnedBackground : theme.listBackground
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = contentView.bounds.width
        separator.frame = CGRect(x: 84, y: contentView.bounds.height - Metrics.pixel, width: w - 84, height: Metrics.pixel)
        avatar.frame = CGRect(x: 16, y: floor((contentView.bounds.height - 60) / 2), width: 60, height: 60)
        dateLabel.sizeToFit()
        dateLabel.frame.origin = CGPoint(x: w - 16 - dateLabel.frame.width, y: 9)
        checkView.frame.origin = CGPoint(x: dateLabel.frame.minX - 4 - checkView.frame.width, y: 13)
        let titleRight = (checkView.isHidden ? dateLabel.frame.minX : checkView.frame.minX) - 6
        titleLabel.frame = CGRect(x: 84, y: 8, width: titleRight - 84, height: 21)
        let badgeWidth: CGFloat = badge.isHidden ? 0 : max(20, ceil(badge.intrinsicContentSize.width) + 12)
        badge.frame = CGRect(x: w - 16 - badgeWidth, y: 38, width: badgeWidth, height: 20)
        badge.layer.cornerRadius = 10
        let textRight = badge.isHidden ? w - 16 : badge.frame.minX - 8
        messageLabel.frame = CGRect(x: 84, y: 29, width: textRight - 84, height: 40)
        messageLabel.sizeToFit()
        messageLabel.frame.size.width = textRight - 84
    }
}

/// Entry point for concept apps.
@MainActor
public enum ShellApp {
    /// Tab bar (Contacts, Calls, Chats, Settings) with the chat list; optionally already inside the first chat.
    public static func makeRoot(chats: [DemoChat] = DemoData.chats, startInChat: Bool = true, features: [ChatFeature] = []) -> UIViewController {
        let list = ChatListViewController(chats: chats, features: features)
        let navigation = UINavigationController(rootViewController: list)
        navigation.tabBarItem = list.tabBarItem
        let tabs = UITabBarController()
        func placeholder(_ title: String, _ icon: String) -> UIViewController {
            let vc = UIViewController()
            vc.view.backgroundColor = .systemBackground
            vc.tabBarItem = UITabBarItem(title: title, image: Graphics.asset(icon), tag: 0)
            return vc
        }
        tabs.viewControllers = [
            placeholder("Contacts", "TGTabIconContacts"),
            placeholder("Calls", "TGTabIconCalls"),
            navigation,
            placeholder("Settings", "TGTabIconSettings"),
        ]
        tabs.selectedIndex = 2
        // Launch argument override: `xcrun simctl launch booted <bundle id> -chatList`
        let forceList = ProcessInfo.processInfo.arguments.contains("-chatList")
        if startInChat, !forceList, !chats.isEmpty {
            list.loadViewIfNeeded()
            list.openChat(at: 0, animated: false)
        }
        return tabs
    }
}
