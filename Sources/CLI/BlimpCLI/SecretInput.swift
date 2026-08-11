import ArgumentParser
import Darwin
import Foundation

/// Resolves a secret from environment, CLI argument, or interactive hidden input.
func resolveSecret(cliValue: String?, environmentKey: String, prompt: String) throws -> String {
    if let value = cliValue { return value }
    if let value = ProcessInfo.processInfo.environment[environmentKey] { return value }

    guard isatty(STDIN_FILENO) == 1 else {
        throw ValidationError("No TTY to prompt for a secret. Set \(environmentKey) or pass it as an argument.")
    }

    print(prompt, terminator: "")
    guard let value = readSecureInput() else {
        throw ValidationError("Failed to read secret input")
    }
    return value
}

private func readSecureInput() -> String? {
    var oldTermios = termios()
    guard tcgetattr(STDIN_FILENO, &oldTermios) == 0 else {
        return readLine()
    }

    var newTermios = oldTermios
    newTermios.c_lflag &= ~UInt(ECHO)
    guard tcsetattr(STDIN_FILENO, TCSANOW, &newTermios) == 0 else {
        return readLine()
    }

    defer {
        tcsetattr(STDIN_FILENO, TCSANOW, &oldTermios)
        print()
    }

    return readLine()
}
