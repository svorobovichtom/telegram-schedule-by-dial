// swift-tools-version: 6.0
import PackageDescription

// Telegram's iOS chat UI rebuilt in plain UIKit, shared by every concept in this workspace.
// Visual values are transcribed from Telegram-iOS (see comments with source paths).
let package = Package(
    name: "TelegramShell",
    platforms: [.iOS("26.0")],
    products: [
        .library(name: "TelegramShell", targets: ["TelegramShell"]),
    ],
    targets: [
        .target(
            name: "TelegramShell",
            resources: [.process("Resources")]
        ),
    ]
)
