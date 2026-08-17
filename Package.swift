// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Blimp",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Blimp", targets: ["BlimpKit"]),
        .library(name: "WebhookKit", targets: ["WebhookKit"]),
        .executable(name: "blimp", targets: ["BlimpCLI"]),
        .executable(name: "blimp-relay", targets: ["BlimpRelay"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "4.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.20.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.2"),
        .package(url: "https://github.com/apple/swift-openapi-generator", exact: "1.10.3"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", exact: "1.8.3"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", exact: "1.1.0"),
        .package(url: "https://github.com/platacard/cronista", from: "1.1.0"),
        .package(url: "https://github.com/platacard/corredor", from: "1.2.0"),
        .package(url: "https://github.com/platacard/dotcontext.git", from: "1.0.1"),
        .package(url: "https://github.com/platacard/gito.git", from: "1.1.0")
    ],
    targets: [
        .cli(
            name: "BlimpCLI",
            dependencies: [
                "BlimpKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Cronista", package: "cronista"),
                .product(name: "Corredor", package: "corredor"),
                .product(name: "DotContext", package: "dotcontext")
            ]
        ),
        .coreApi(name: "Auth"),
        .coreApi(name: "ClientTransport"),

        .api(name: "AppsAPI"),
        .api(name: "ProvisioningAPI"),
        .api(name: "TestflightAPI"),
        .api(name: "WebhooksAPI"),

        .core(name: "ASCCredentials"),
        .core(
            name: "DeployHelpers",
            dependencies: [
                .product(name: "Cronista", package: "cronista"),
                .product(name: "Corredor", package: "corredor")
            ]
        ),
        
        .domain(
            name: "BlimpKit",
            dependencies: [
                "Uploader",
                "AppsAPI",
                "ProvisioningAPI",
                "TestflightAPI",
                "WebhooksAPI",
                "JWTProvider",
                "DeployHelpers",
                .product(name: "Cronista", package: "cronista"),
                .product(name: "Corredor", package: "corredor"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Gito", package: "gito")
            ]
        ),
        .domain(
            name: "WebhookKit",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto")
            ]
        ),
        .executableTarget(
            name: "BlimpRelay",
            dependencies: [
                "WebhookKit",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIOCore", package: "swift-nio")
            ],
            path: "Sources/Relay"
        ),
        .domain(
            name: "JWTProvider",
            dependencies: [
                "ASCCredentials",
                .product(name: "Cronista", package: "cronista"),
                .product(name: "Crypto", package: "swift-crypto")
            ]
        ),
        .domain(
            name: "Uploader",
            dependencies: [
                "ASCCredentials",
                "AppsAPI",
                "TestflightAPI",
                "JWTProvider",
                .product(name: "Cronista", package: "cronista"),
                .product(name: "Corredor", package: "corredor"),
                .product(name: "Crypto", package: "swift-crypto")
            ]
        ),

        // MARK: - Tests

        .apiTest(name: "AppsAPI"),
        .apiTest(name: "ProvisioningAPI", dependencies: [
            "ProvisioningAPI",
            "ASCCredentials",
            "JWTProvider",
            .product(name: "Crypto", package: "swift-crypto")
        ]),
        .apiTest(name: "TestflightAPI"),
        .coreTest(name: "DeployHelpers", resources: [.process("Resources")]),
        .domainTest(name: "Uploader"),
        .domainTest(name: "JWTProvider"),
        .domainTest(name: "WebhookKit"),
        .testTarget(
            name: "BlimpRelayTests",
            dependencies: ["BlimpRelay"],
            path: "Tests/Relay"
        ),
        .testTarget(
            name: "BlimpKitTests",
            dependencies: [
                "BlimpKit",
                .product(name: "Gito", package: "gito")
            ],
            path: "Tests/Domain/BlimpKit"
        )
    ]
)

// MARK: - Extensions

extension Target {
    
    static func coreApi(name: String) -> Target {
        .target(
            name: name,
            dependencies: [
                .product(name: "Cronista", package: "cronista"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession")
            ],
            path: "Sources/API/Core/\(name)"
        )
    }
    
    static func api(
        name: String,
        dependencies: [Target.Dependency] = [],
        resources: [Resource] = []
    ) -> Target {
        .target(
            name: name,
            dependencies: [
                "Auth",
                "ClientTransport",
                "JWTProvider",
                "ASCCredentials",
                .product(name: "Cronista", package: "cronista"),
                .product(name: "Corredor", package: "corredor"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession")
            ],
            path: "Sources/API/\(name)",
            resources: resources
        )
    }
    
    static func core(
        name: String,
        dependencies: [Target.Dependency] = [],
        plugins: [Target.PluginUsage] = [],
        resources: [Resource] = []
    ) -> Target {
        .target(
            name: name,
            dependencies: dependencies,
            path: "Sources/Core/\(name)",
            resources: resources,
            plugins: plugins
        )
    }

    static func domain(
        name: String,
        dependencies: [Target.Dependency] = [],
        resources: [Resource] = []
    ) -> Target {
        .target(
            name: name,
            dependencies: dependencies,
            path: "Sources/Domain/\(name)",
            resources: resources
        )
    }

    static func cli(
        name: String,
        dependencies: [Target.Dependency] = [],
        resources: [Resource] = []
    ) -> Target {
        .executableTarget(
            name: name,
            dependencies: dependencies,
            path: "Sources/CLI/\(name)",
            resources: resources
        )
    }

    static func apiTest(
        name: String,
        dependencies: [Target.Dependency]? = nil,
        resources: [Resource] = []
    ) -> Target {
        .testTarget(
            name: "\(name)Tests",
            dependencies: dependencies ?? [Dependency(stringLiteral: name), "ASCCredentials", "JWTProvider"],
            path: "Tests/API/\(name)",
            resources: resources
        )
    }

    static func coreTest(
        name: String,
        resources: [Resource] = []
    ) -> Target {
        .testTarget(
            name: "\(name)Tests",
            dependencies: [Dependency(stringLiteral: name)],
            path: "Tests/Core/\(name)",
            resources: resources
        )
    }

    static func domainTest(
        name: String,
        resources: [Resource] = []
    ) -> Target {
        .testTarget(
            name: "\(name)Tests",
            dependencies: [Dependency(stringLiteral: name)],
            path: "Tests/Domain/\(name)",
            resources: resources
        )
    }
}
