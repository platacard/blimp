// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Blimp",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Blimp", targets: ["BlimpKit"]),
        .executable(name: "blimp", targets: ["BlimpCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "4.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.2"),
        .package(url: "https://github.com/apple/swift-openapi-generator", exact: "1.10.3"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", exact: "1.8.3"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", exact: "1.1.0"),
        .package(url: "https://github.com/platacard/cronista", exact: "1.0.3"),
        .package(url: "https://github.com/platacard/corredor", exact: "1.0.2"),
        .package(url: "https://github.com/platacard/dotcontext.git", exact: "1.0.1")
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
                "Transporter",
                "AppsAPI",
                "ProvisioningAPI",
                "TestflightAPI",
                "JWTProvider",
                "DeployHelpers",
                .product(name: "Cronista", package: "cronista"),
                .product(name: "Corredor", package: "corredor")
            ]
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
            name: "Transporter",
            dependencies: [
                "ASCCredentials",
                .product(name: "Cronista", package: "cronista"),
                .product(name: "Corredor", package: "corredor")
            ]
        ),

        // MARK: - Tests

        .apiTest(name: "AppsAPI"),
        .apiTest(name: "TestflightAPI"),
        .coreTest(name: "DeployHelpers", resources: [.process("Resources")]),
        .domainTest(name: "Transporter"),
        .domainTest(name: "BlimpKit")
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
        resources: [Resource] = []
    ) -> Target {
        .testTarget(
            name: "\(name)Tests",
            dependencies: [Dependency(stringLiteral: name), "ASCCredentials", "JWTProvider"],
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
