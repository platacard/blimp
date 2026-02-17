# AGENT INSTRUCTIONS

ALWAYS check this manual first before acting.

This repo is a modern Swift CLI alternative to Fastlane. Your task is to improve the repo when the user asks you to. Always start your feature implementation in TDD manner, i.e. start with a unit test. Ensure the system is fully intact on every step, i.e. run unit tests frequently.

## Modern Swift 6 CLI Development Guide

This document outlines the standard for high-performance, race-safe Swift command-line tools. It focuses on **Strict Concurrency** and **Structured Concurrency** while eliminating legacy patterns.

---

## 1. Best Practices: Modern Usage

### A. The Async Entry Point
In 2026, we avoid `main.swift` top-level code in favor of a structured `@main` entry point using `AsyncParsableCommand`.

```swift
import Foundation
import ArgumentParser // Standard CLI library

@main
struct ModernTool: AsyncParsableCommand {
    @Option(name: .shortAndLong, help: "Number of threads to simulate")
    var count: Int = 5

    // GOOD: Native async entry point ensures the tool waits for all tasks
    func run() async throws {
        print("🚀 Starting modern Swift 6 process...")

        let tracker = ProgressTracker()

        // GOOD: Structured Concurrency (TaskGroup)
        // Automatically manages child task lifetimes
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 1...count {
                group.addTask {
                    try await performWork(id: i, tracker: tracker)
                }
            }
        }

        let finalCount = await tracker.total
        print("✅ Finished. Total items processed: \(finalCount)")
    }
}
```

Use code with caution.

B. Thread-Safe State (Actors)
Use actors to manage shared mutable state. This replaces the manual DispatchQueue locks of previous years.
```swift
// GOOD: Protects shared state with compile-time safety
actor ProgressTracker {
    private(set) var total = 0

    func increment() {
        total += 1
    }
}
```

C. Cooperative Cancellation

CLI tools must respond to user interrupts (Ctrl+C). Modern Swift handles this via Task.checkCancellation().
swift
func performWork(id: Int, tracker: ProgressTracker) async throws {
    // GOOD: Periodically check if the user or system cancelled the task
    try Task.checkCancellation()

    // Simulate non-blocking work
    try await Task.sleep(for: .seconds(Double.random(in: 0.5...1.5)))

    await tracker.increment()
    print("  [Task \(id)] Work complete.")
}
Use code with caution.

2. Anti-Patterns: Codes to Avoid
❌ Anti-Pattern: Unstructured "Fire-and-Forget" Tasks
In a CLI, the program terminates as soon as run() returns. Using Task { } allows work to start, but the program will likely exit before it finishes.
```swift
// BAD: This work will be killed prematurely
func run() {
    Task {
        await someLongProcess() // Tool exits before this completes
    }
}
```

❌ Anti-Pattern: Blocking the Concurrent Thread Pool
Calling synchronous, blocking functions inside an async function prevents the Swift runtime from reusing that thread for other tasks.

```swift
// BAD: Blocks a thread in the concurrency pool
func processData() async {
    let data = try! Data(contentsOf: someLargeFileURL) // Synchronous/Blocking
}

// GOOD: Use async-native file I/O or URLSession
```

❌ Anti-Pattern: Force Unwrapping and Manual Casting
Modern Swift emphasizes safety. Using ! leads to fragile CLI tools that provide no helpful error messages before crashing.
```swift
// BAD: Crash without explanation if the URL is malformed
let url = URL(string: userInput)!

// GOOD: Throw a descriptive error
guard let url = URL(string: userInput) else {
    throw ValidationError("Invalid URL provided.")
}
```

❌ Anti-Pattern: Silencing Errors
Using try? in a CLI is problematic because the user loses all diagnostic information about why a command failed.
```swift
// BAD: User has no idea why the file failed to save
try? data.write(to: path)

// GOOD: Propagate error so it can be printed to stderr
try data.write(to: path)
```

❌ Anti-Pattern: Editing Generated Code or OpenAPI Specs
NEVER edit:
- Files in `Generated/` directories - auto-generated and will be overwritten
- OpenAPI spec files (`openapi.json`) - these are 3rd party specs from Apple that must remain unchanged

```swift
// BAD: Editing Sources/API/*/Generated/Types.swift
// BAD: Editing Sources/API/*/openapi.json

// GOOD: Handle at domain layer (TestflightAPI wrapper for example)
```

❌ Anti-Pattern: Excessive verbose comments

```swift
// BAD: excessive comments

// Should have created a certificate
XCTAssertEqual(mockAPI.certificates.count, 1)
let cert = mockAPI.certificates.first
XCTAssertEqual(cert?.type, .development)

// Should have stored certificate in git (cer + p12)
// Cert ID is generated, so we need to use the one from API
guard let createdCert = cert else { return }
let certPath = "certs/ios/DEVELOPMENT/\(createdCert.id).cer"
let p12Path = "certs/ios/DEVELOPMENT/\(createdCert.id).p12"

// GOOD: Be concise and don't pour water with your comments

XCTAssertEqual(mockAPI.certificates.count, 1)
let cert = mockAPI.certificates.first
XCTAssertEqual(cert?.type, .development)

guard let cert else { return }

let certPath = "certs/ios/DEVELOPMENT/\(createdCert.id).cer"
let p12Path = "certs/ios/DEVELOPMENT/\(createdCert.id).p12"
```

❌ Anti-Pattern: Outdated Optional Unwrapping
Since Swift 5.7, use shorthand `if let` / `guard let` when the unwrapped variable has the same name.
```swift
// BAD: Redundant variable name
if let name = name {
    print(name)
}

// GOOD: Shorthand syntax (Swift 5.7+)
if let name {
    print(name)
}
```

❌ Anti-Pattern: Premature Deprecation
This is a pre-1.0 project. Don't use `@available(*, deprecated)` - just delete or rename directly.
```swift
// BAD: Adding deprecation annotations in a pre-1.0 project
@available(*, deprecated, renamed: "ProcessingState")
typealias BetaProcessingState = ProcessingState

// GOOD: Just delete or rename directly - no backward compatibility needed yet
```

❌ Anti-Pattern: Private Functions at the Top
Put private methods in a separate `private extension` at the bottom of the file. Public methods should appear first.
Exception: allowed if the entire type is private.
```swift
// BAD: Private function mixed with public API
extension MyType {
    private func helperFunction() { }  // ← Don't put this here

    public func publicAPI() { }
}

// GOOD: Private extension at bottom of file
public extension MyType {
    func publicAPI() { }
}

// ... other extensions ...

private extension MyType {
    func helperFunction() { }
}
```

❌ Anti-Pattern: Redundant Control Flow
Don't check a condition before a switch and then handle the same cases inside the switch. Use one control structure.
```swift
// BAD: Non-linear, reader must jump between if-check, switch, and helper function
if let terminalError = state.asTerminalError {
    throw mapToError(terminalError)
}
switch state {
case .processing: ...
case .terminalCase: break // "handled above"
}

// GOOD: Linear, all cases handled in one place
switch state {
case .processing: ...
case .terminalCase: throw Error.terminalCase
}
```

❌ Anti-Pattern: Explicit Closure Instead of KeyPath
When accessing a single property in `map`, `compactMap`, `filter`, etc., use keypath syntax for cleaner code.
```swift
// BAD: Verbose closure syntax
let ids = items.compactMap { $0.id }
let names = users.map { $0.name }

// GOOD: KeyPath syntax
let ids = items.compactMap(\.id)
let names = users.map(\.name)
```

## System Overview

Swift 6.2+ CLI tool for iOS/macOS app deployment to TestFlight/App Store. Alternative to Fastlane.

### Structure

```
Sources/
├── API/           # App Store Connect API (OpenAPI generated)
│   ├── AppsAPI/           # App lookup
│   ├── TestflightAPI/     # Builds, beta groups, review
│   ├── ProvisioningAPI/   # Certs, profiles, devices
│   └── Core/Auth/         # JWT middleware
├── CLI/BlimpCLI/  # Commands: takeoff, approach, land, hangar, maintenance
├── Core/          # Credentials, plist helpers
└── Domain/BlimpKit/
    ├── Stages/    # 1_Maintenance, 2_TakeOff, 3_Approach, 4_Land
    ├── Git/       # Profile storage
    └── Uploader/  # IPA upload
```

### Flight Stages

1. **Maintenance** (Hangar) - Full cert/profile/device management via App Store Connect API with Git storage. Certificates are encrypted (AES-256-GCM), profiles are stored unencrypted. Handles development, distribution, and ad-hoc profiles with automatic device fetching.
2. **TakeOff** - `xcodebuild archive/export`
3. **Approach** - Upload IPA, poll processing
4. **Land** - Set beta groups, submit review

### Commands

```bash
# Build & Deploy
blimp takeoff --scheme App --workspace App.xcworkspace --deploy-config config.plist
blimp approach --bundle-id com.app --ipa-path build/App.ipa --app-version 1.0 --build-number 1
blimp land --bundle-id com.app --build-id 123 "Beta Testers"

# Maintenance (Hangar) - Certificate & Profile Management
blimp maintenance init --git-url git@github.com:org/certs.git
blimp maintenance list-devices --platform ios
blimp maintenance register-device UDID-123 "iPhone 15" --platform ios
blimp maintenance list-certs --type DEVELOPMENT
blimp maintenance generate-cert --type DEVELOPMENT --platform ios --storage-path ./certs --passphrase pass
blimp maintenance remove-cert CERT-ID
blimp maintenance list-profiles --name "Blimp*"
blimp maintenance sync-profiles --bundle-ids com.app --platform ios --type development --storage-path ./certs
blimp maintenance install-profiles
blimp maintenance install-profiles --bundle-id "com.app.*"
blimp maintenance install-profiles --platform macos --type appstore
blimp maintenance remove-profile PROFILE-ID
```

### Environment

```bash
export APPSTORE_CONNECT_API_KEY_ID=...
export APPSTORE_CONNECT_API_ISSUER_ID=...
export APPSTORE_CONNECT_API_PRIVATE_KEY=...  # base64, no headers
```

## Build

```bash
swift build
swift test
```

## Storage Structure

Git storage follows this structure:
```
certificates/{type}/{cert-id}.p12                        # Universal certs (DISTRIBUTION, DEVELOPMENT) - no platform dir
certificates/{platform}/{type}/{cert-id}.p12             # Platform-specific certs (IOS_DEVELOPMENT, etc.)
profiles/{platform}/{type}/{bundle-id}.mobileprovision   # Unencrypted
```

Profile installation (`install-profiles`) extracts UUID via `security cms -D` and copies to:
`~/Library/MobileDevice/Provisioning Profiles/{uuid}.mobileprovision`

## Key Protocols

- `JWTProviding` - Token generation
- `ProvisioningService` - API abstraction (`CertificateService`, `ProfileService`, `DeviceService`)
- `GitManaging` - Profile storage
- `ShellExecuting` - Shell command abstraction (for testability)
- `AppStoreConnectUploader` - Upload abstraction
- `BuildQueryService` - Build polling and status (TestflightAPI)
- `BetaManagementService` - Beta groups and review (TestflightAPI)
- `AppQueryService` - App lookup (AppsAPI)

## Concurrency

- Actors: `GitRepo`, `AppStoreConnectAPIUploader`
- Sendable structs with `nonisolated(unsafe)` for thread-safe external deps (Cronista logger)
- No `@MainActor` on CLI commands (Swift 6.2 AsyncParsableCommand compatibility)

---

## Testing Guide

### Philosophy: Tests as Snapshots
Treat tests as **snapshots of working system state**. Each test captures correct behavior at a key decision point:
- State transitions (e.g., `processing` → `valid`/`failed`/`invalid`)
- Error handling paths
- Data transformations (e.g., device model → human-readable name)

### Protocol-Based Testability Pattern

When a stage/component creates API clients internally, extract protocols for dependency injection:

```swift
// 1. Define protocol in API module (e.g., Sources/API/TestflightAPI/TestflightProtocols.swift)
public protocol BuildQueryService: Sendable {
    func getBuildID(appId: String, appVersion: String, buildNumber: String) async throws -> String?
}

// 2. Conform existing implementation
extension TestflightAPI: BuildQueryService {}

// 3. Update stage to accept protocol with convenience initializer
public struct Approach {
    private let buildQueryService: BuildQueryService

    // Testable initializer
    public init(buildQueryService: BuildQueryService) {
        self.buildQueryService = buildQueryService
    }

    // Production convenience initializer
    public init(jwtProvider: JWTProviding = DefaultJWTProvider()) {
        self.init(buildQueryService: TestflightAPI(jwtProvider: jwtProvider))
    }
}
```

### Public Initializers for Testability

Structs with public properties still have **internal** memberwise initializers. Add explicit public inits for types used in tests:

```swift
// BAD: Can't create in tests
public struct BuildProcessingResult: Sendable {
    public let processingState: BetaProcessingState
    public let buildBundleID: String
}

// GOOD: Testable
public struct BuildProcessingResult: Sendable {
    public let processingState: BetaProcessingState
    public let buildBundleID: String

    public init(processingState: BetaProcessingState, buildBundleID: String) {
        self.processingState = processingState
        self.buildBundleID = buildBundleID
    }
}
```

### Mock Patterns

Mocks live in `Tests/Domain/BlimpKit/Mocks.swift`. Follow this pattern:

```swift
class MockBuildQueryService: BuildQueryService, @unchecked Sendable {
    // Configurable responses
    var buildIdResponses: [String?] = []
    var errorToThrow: Error?

    // Call tracking
    var getBuildIDCallCount = 0

    func getBuildID(...) async throws -> String? {
        if let error = errorToThrow { throw error }
        let index = min(getBuildIDCallCount, buildIdResponses.count - 1)
        getBuildIDCallCount += 1
        return buildIdResponses.isEmpty ? nil : buildIdResponses[max(0, index)]
    }
}
```

Key patterns:
- Use `@unchecked Sendable` for test doubles (tests are single-threaded)
- Track calls for verification assertions
- Support sequential responses for polling loops
- Support error injection via `errorToThrow`

### Test File Structure

```
Tests/Domain/BlimpKit/
├── Mocks.swift                    # All mock implementations
├── ApproachStageTests.swift       # Approach stage behavior tests
├── LandStageTests.swift           # Land stage behavior tests
├── TakeOffStageTests.swift        # Argument construction tests
├── CertificateManagerTests.swift  # Certificate workflows
├── ProfileSyncCoordinatorTests.swift  # Profile sync logic
└── ...
```

### What to Test per Stage

| Stage | Test Focus |
|-------|------------|
| **Approach** | Upload success/failure, build polling state transitions, device model mapping |
| **Land** | Beta group assignment, changelog submission, review submission |
| **TakeOff** | Argument construction (`bashArgument` values), Configuration parsing |
| **Maintenance** | Tested via CertificateManager and ProfileSyncCoordinator |

### Running Tests

```bash
swift test                           # Run all tests
swift test --filter ApproachStage    # Run specific test suite
swift test 2>&1 | grep "Executed"    # Check test count
```
