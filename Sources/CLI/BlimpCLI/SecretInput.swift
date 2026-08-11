import ArgumentParser
import Darwin
import Foundation

/// Resolves a secret from environment, CLI argument, or interactive hidden input.
func resolveSecret(cliValue: String?, environmentKey: String, prompt: String) throws -> String {
    // Environment variable first (CI-friendly)
    if let value = ProcessInfo.processInfo.environment[environmentKey] { return value }
    if let value = cliValue { return value }

    print(prompt, terminator: "")
    guard let value = readSecureInput() else {
        throw ValidationError("Failed to read secret input")
    }
    return value
}

private func readSecureInput() -> String? {
    var oldTermios = termios()
    tcgetattr(STDIN_FILENO, &oldTermios)

    var newTermios = oldTermios
    newTermios.c_lflag &= ~UInt(ECHO)
    tcsetattr(STDIN_FILENO, TCSANOW, &newTermios)

    let result = readLine()

    tcsetattr(STDIN_FILENO, TCSANOW, &oldTermios)
    print()

    return result
}
