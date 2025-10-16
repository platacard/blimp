import ArgumentParser
import JWTProvider
import TestflightAPI
import AppsAPI
import Cronista

struct Clearance: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clearance",
        abstract: "Invite beta testers in TestFlight"
    )
    
    @Option(help: """
    A new developer is required to accept the invite first. 
    Then use betaTester level to invite them to beta groups.
    """)
    var clearanceLevel: ClearanceLevel = .betaTester
    
    @Option(help: "Internal/External email to invite to. Internal groups require the developer invite.")
    var email: String
    
    @Option
    var firstName: String
    
    @Option(help: "Just the last name, no special symbols like '_'")
    var lastName: String = "Blimp Invite"

    @Option(parsing: .upToNextOption, help: "App's bundle ids to invite to")
    var bundleIds: [String] = []
    
    @Option(parsing: .upToNextOption, help: "Beta groups to invite to")
    var betaGroups: [String] = []
    
    var logger: Cronista {
        Cronista(module: "Blimp", category: "Hangar Clearance")
    }
    
    func run() async throws {
        let jwtProvider = DefaultJWTProvider()
        let appsAPI = AppsAPI(jwtProvider: jwtProvider)
        let tfAPI = TestflightAPI(jwtProvider: jwtProvider)
        
        logger.info("Email: \(email)")
        logger.info("Name: \(firstName) \(lastName)")
        
        if !bundleIds.isEmpty && !betaGroups.isEmpty {
            logger.info("Bundle ids: \(bundleIds.joined(separator: ", "))")
            logger.info("Beta groups: \(betaGroups.joined(separator: ", "))")
        }
        
        switch clearanceLevel {
        case .developer:
            try await tfAPI.inviteDeveloper(email: email, firstName: firstName, lastName: lastName)
            logger.info("Invited \(email) with developer role")
        case .betaTester:
            guard !betaGroups.isEmpty && !bundleIds.isEmpty else {
                throw ValidationError("Beta groups and bundle ids are required for beta tester invite")
            }
            
            var appIds: [String] = []
            for bundleId in bundleIds {
                let appId = try await appsAPI.getAppId(bundleId: bundleId)
                logger.info("App id: \(appId) for bundle id: \(bundleId)")
                appIds.append(appId)
            }
            
            try await tfAPI.inviteBetaTester(
                appIds: appIds,
                betaGroups: betaGroups,
                email: email,
                firstName: firstName,
                lastName: lastName
            )
        }
    }
}

enum ClearanceLevel: String, ExpressibleByArgument {
    case developer
    case betaTester
}
