// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WebDAVClient",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "WebDAVClient", targets: ["WebDAVClient"])
    ],
    targets: [
        .executableTarget(
            name: "WebDAVClient",
            path: "WebDAVClient"
        )
    ]
)
