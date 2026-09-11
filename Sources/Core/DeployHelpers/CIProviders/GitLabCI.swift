import Foundation

/// `blimp.env` in `$CI_PROJECT_DIR`, published by the job as a dotenv
/// artifact report; GitLab then injects its variables into dependent jobs.
public struct GitLabCI: CIProvider {
    public static let name = "GitLab CI"
    public static let outputFileName = "blimp.env"

    public let outputFile: URL?
    public let summaryFile: URL? = nil

    public init?(environment: [String: String]) {
        guard environment["GITLAB_CI"] == "true",
              let projectDir = environment["CI_PROJECT_DIR"], !projectDir.isEmpty
        else { return nil }
        outputFile = URL(fileURLWithPath: projectDir).appendingPathComponent(Self.outputFileName)
    }

    public func entry(name: String, value: String) throws -> String {
        try Dotenv.entry(name: name, value: value)
    }
}
