// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "GitHubActionsMenu",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "GitHubActionsMenu",
            path: "Sources/GitHubActionsMenu"
        )
    ]
)
