import UIKit

public struct DemoPeer: Hashable, Sendable {
    public var name: String
    /// Image in the asset catalog of the app or of TelegramShell. Nil draws Telegram's colored initials avatar.
    public var avatar: String?
    /// Index into Telegram's 7 avatar gradients when there is no image.
    public var colorIndex: Int
    public var status: String

    public init(name: String, avatar: String? = nil, colorIndex: Int = 0, status: String = "last seen recently") {
        self.name = name
        self.avatar = avatar
        self.colorIndex = colorIndex
        self.status = status
    }

    public var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

public struct DemoMessage: Hashable, Sendable, Identifiable {
    public enum Status: Hashable, Sendable { case sending, sent, read }

    public var id: UUID
    public var text: String
    public var isOutgoing: Bool
    public var date: Date
    public var status: Status
    /// Name shown above incoming messages in groups.
    public var author: String?
    /// A photo message: the images' file names in the app bundle ("boat.jpg"); two or more make an album. The text
    /// is not shown with them.
    public var photos: [String]
    public var photo: String? { photos.first }

    public init(_ text: String, outgoing: Bool, at time: String, status: Status = .read, author: String? = nil, day: Int = 0) {
        self.id = UUID()
        self.text = text
        self.isOutgoing = outgoing
        self.date = DemoMessage.date(time, dayOffset: day)
        self.status = status
        self.author = author
        self.photos = []
    }

    public init(id: UUID = UUID(), text: String, isOutgoing: Bool, date: Date, status: Status = .read, author: String? = nil,
                photo: String? = nil, photos: [String] = []) {
        self.id = id
        self.text = text
        self.isOutgoing = isOutgoing
        self.date = date
        self.status = status
        self.author = author
        self.photos = photo.map { [$0] + photos } ?? photos
    }

    /// "12:41" today (or `dayOffset` days ago).
    static func date(_ time: String, dayOffset: Int) -> Date {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = parts.first ?? 12
        components.minute = parts.count > 1 ? parts[1] : 0
        let day = Calendar.current.date(from: components) ?? Date()
        return Calendar.current.date(byAdding: .day, value: -dayOffset, to: day) ?? day
    }
}

public struct DemoChat: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var peer: DemoPeer
    public var messages: [DemoMessage]
    public var unreadCount: Int
    public var isPinned: Bool
    public var isMuted: Bool

    public init(peer: DemoPeer, messages: [DemoMessage], unreadCount: Int = 0, isPinned: Bool = false, isMuted: Bool = false) {
        self.id = UUID()
        self.peer = peer
        self.messages = messages
        self.unreadCount = unreadCount
        self.isPinned = isPinned
        self.isMuted = isMuted
    }
}

/// A concept hooks into the chat through this. Install as many as you need; they get the chat once it is laid out.
@MainActor
public protocol ChatFeature: AnyObject {
    func chatDidLoad(_ chat: ChatViewController)
}
