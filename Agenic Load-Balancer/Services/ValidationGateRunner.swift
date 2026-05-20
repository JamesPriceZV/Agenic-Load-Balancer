//
//  ValidationGateRunner.swift
//  Agenic Load-Balancer
//
//  Phase 7.6: validation gate values and test doubles.
//

import Foundation

struct ValidationGateResult: Sendable, Hashable {
    var command: String
    var exitCode: Int32
    var outputExcerpt: String
    var startedAt: Date
    var endedAt: Date

    var passed: Bool { exitCode == 0 }
}

protocol ValidationGateRunning: Sendable {
    func run(command: String, workingDirectory: String) async -> ValidationGateResult
}

struct ShellValidationGateRunner: ValidationGateRunning {
    private let shellPath: String
    private let outputLimit: Int
    private let now: @Sendable () -> Date

    init(
        shellPath: String = "/bin/zsh",
        outputLimit: Int = 6_000,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.shellPath = shellPath
        self.outputLimit = outputLimit
        self.now = now
    }

    func run(command: String, workingDirectory: String) async -> ValidationGateResult {
        let shellPath = shellPath
        let outputLimit = outputLimit
        let startedAt = now()

        return await Task.detached(priority: .userInitiated) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: shellPath)
            process.arguments = ["-lc", command]
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let rawOutput = String(data: data, encoding: .utf8) ?? ""
                return ValidationGateResult(
                    command: command,
                    exitCode: process.terminationStatus,
                    outputExcerpt: Self.truncated(rawOutput, limit: outputLimit),
                    startedAt: startedAt,
                    endedAt: Date()
                )
            } catch {
                return ValidationGateResult(
                    command: command,
                    exitCode: 127,
                    outputExcerpt: Self.truncated(error.localizedDescription, limit: outputLimit),
                    startedAt: startedAt,
                    endedAt: Date()
                )
            }
        }.value
    }

    private static func truncated(_ output: String, limit: Int) -> String {
        guard output.count > limit else { return output }
        return "[truncated to last \(limit) chars]\n" + String(output.suffix(limit))
    }
}

struct ScriptedValidationGateRunner: ValidationGateRunning {
    let result: ValidationGateResult

    func run(command _: String, workingDirectory _: String) async -> ValidationGateResult {
        result
    }
}
