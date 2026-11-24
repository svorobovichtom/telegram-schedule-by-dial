import Foundation

/// Conversations for demo videos. Edit freely: the text should look like a real chat, not lorem ipsum.
public enum DemoData {
    public static let yuliya = DemoPeer(name: "Yuliya Miniuk", avatar: "AvatarYuliya", colorIndex: 0, status: "online")
    public static let john = DemoPeer(name: "John Ivanov", colorIndex: 4, status: "last seen recently")
    public static let study = DemoPeer(name: "Study Group", colorIndex: 2, status: "5 members, 2 online")
    public static let thomas = DemoPeer(name: "Thomas", colorIndex: 1, status: "last seen at 11:22")
    public static let jessica = DemoPeer(name: "Jessica", colorIndex: 6, status: "last seen yesterday")

    public static let yuliyaChat = DemoChat(peer: yuliya, messages: [
        DemoMessage("Are we still on for Saturday?", outgoing: false, at: "18:02", day: 1),
        DemoMessage("Yes! I booked the boat for 10", outgoing: true, at: "18:05", day: 1),
        DemoMessage("Perfect 🙌", outgoing: false, at: "18:05", day: 1),
        DemoMessage("Morning! Did you see the forecast?", outgoing: false, at: "12:30"),
        DemoMessage("Sunny all day, no wind after 4", outgoing: false, at: "12:30"),
        DemoMessage("Then let's stay for the sunset. The spot at 7 is the best on that side of the bay", outgoing: true, at: "12:34"),
        DemoMessage("Deal. I'll bring the camera", outgoing: false, at: "12:36"),
        DemoMessage("And the drone?", outgoing: true, at: "12:37"),
        DemoMessage("Battery is dead, charging it tonight", outgoing: false, at: "12:38"),
        DemoMessage("Sunset spot at 7? I'll bring the camera", outgoing: false, at: "12:41"),
    ])

    public static let chats: [DemoChat] = [
        yuliyaChat,
        DemoChat(peer: john, messages: [DemoMessage("Sent you 17 Grams 💎", outgoing: false, at: "12:20")], unreadCount: 1),
        DemoChat(peer: study, messages: [DemoMessage("calculations.zip", outgoing: false, at: "11:58", author: "Emma")], isMuted: true),
        DemoChat(peer: thomas, messages: [DemoMessage("Happy Birthday! 🎉", outgoing: false, at: "11:22")], unreadCount: 3, isMuted: true),
        DemoChat(peer: jessica, messages: [DemoMessage("See you there", outgoing: true, at: "10:47")]),
    ]
}
