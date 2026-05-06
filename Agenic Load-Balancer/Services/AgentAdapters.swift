//
//  AgentAdapters.swift
//  Agenic Load-Balancer
//
//  Created by OpenAI Codex on 5/5/26.
//

import Foundation

struct AgentCommand: Identifiable, Sendable {
    let id: UUID
    let providerID: String
    let executablePath: String
    let arguments: [String]
    let environment: [String: String]
    let workingDirectory: String?
    let requiresApproval: Bool

    init(
        id: UUID = UUID(),
        providerID: String,
        executablePath: String,
        arguments: [String],
        environment: [String: String] = [:],
        workingDirectory: String? = nil,
        requiresApproval: Bool = true
    ) {
        self.id = id
        self.providerID = providerID
        self.executablePath = executablePath
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.requiresApproval = requiresApproval
    }

    var displayCommand: String {
        ([executablePath] + arguments)
            .map { value in
                value.contains(" ") ? "\"\(value)\"" : value
            }
            .joined(separator: " ")
    }
}

enum AgentProcessEvent: Sendable {
    case started(command: String)
    case standardOutput(String)
    case standardError(String)
    case finished(exitCode: Int32)
}

enum AgentProcessError: Error, Sendable, LocalizedError {
    case missingExecutable(String)
    case invalidCommand(String)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingExecutable(let name): "Missing executable: \(name)"
        case .invalidCommand(let message): message
        case .launchFailed(let message): message
        }
    }
}

protocol AgentCLIAdapter: Sendable {
    var providerID: String { get }
    func availability(for provider: AgentProviderSnapshot) async -> ProviderHealthSnapshot
    func buildCommand(
        prompt: String,
        projectPath: String?,
        mode: AgentExecutionMode,
        provider: AgentProviderSnapshot
    ) throws -> AgentCommand
}

struct GenericCLIAdapter: AgentCLIAdapter {
    let providerID: String
    /// Optional user-defined command profile that overrides the catalog
    /// defaults for this provider. When `isEnabled` is true the adapter
    /// uses `executablePathOverride`, parsed `argumentLines`, and the env
    /// dictionary instead of the per-provider switch in
    /// `defaultCommandArguments`.
    let commandProfile: ProviderCommandProfileSnapshot?
    private let executableResolver: CLIExecutableResolving

    init(
        providerID: String,
        commandProfile: ProviderCommandProfileSnapshot? = nil,
        executableResolver: CLIExecutableResolving = CLIExecutableResolver()
    ) {
        self.providerID = providerID
        self.commandProfile = commandProfile
        self.executableResolver = executableResolver
    }

    func availability(for provider: AgentProviderSnapshot) async -> ProviderHealthSnapshot {
        guard provider.isEnabled else {
            return ProviderHealthSnapshot(
                providerID: provider.identifier,
                availabilityState: .disabled,
                detectedVersion: nil,
                message: "Provider is disabled.",
                checkedAt: Date()
            )
        }

        // Profile override path: when the user supplied a custom executable
        // path and enabled the profile, treat that path as the source of
        // truth for availability, including for "custom" API-only providers.
        if let profile = commandProfile, profile.isEnabled,
           let overridePath = profile.executablePathOverride,
           !overridePath.isEmpty {
            if FileManager.default.isExecutableFile(atPath: overridePath) {
                let version = await executableResolver.versionString(executablePath: overridePath)
                return ProviderHealthSnapshot(
                    providerID: provider.identifier,
                    availabilityState: .available,
                    detectedVersion: version,
                    message: "Detected via custom command profile at \(overridePath).",
                    checkedAt: Date()
                )
            } else {
                return ProviderHealthSnapshot(
                    providerID: provider.identifier,
                    availabilityState: .missing,
                    detectedVersion: nil,
                    message: "Custom command profile path is not executable: \(overridePath).",
                    checkedAt: Date()
                )
            }
        }

        guard provider.binaryName != "custom" else {
            return ProviderHealthSnapshot(
                providerID: provider.identifier,
                availabilityState: .unknown,
                detectedVersion: nil,
                message: "Custom/API profile requires user configuration.",
                checkedAt: Date()
            )
        }

        guard let executablePath = executableResolver.resolveExecutable(named: provider.binaryName) else {
            return ProviderHealthSnapshot(
                providerID: provider.identifier,
                availabilityState: .missing,
                detectedVersion: nil,
                message: "`\(provider.binaryName)` was not found on PATH or common developer-tool paths.",
                checkedAt: Date()
            )
        }

        let version = await executableResolver.versionString(executablePath: executablePath)
        return ProviderHealthSnapshot(
            providerID: provider.identifier,
            availabilityState: .available,
            detectedVersion: version,
            message: "Detected at \(executablePath).",
            checkedAt: Date()
        )
    }

    func buildCommand(
        prompt: String,
        projectPath: String?,
        mode: AgentExecutionMode,
        provider: AgentProviderSnapshot
    ) throws -> AgentCommand {
        guard provider.supports(mode) else {
            throw AgentProcessError.invalidCommand("\(provider.displayName) does not support \(mode.label).")
        }

        let coordinationPrompt = Self.coordinationPrompt(prompt: prompt, mode: mode)

        // Profile override path takes precedence when the user enabled it.
        if let profile = commandProfile, profile.isEnabled {
            let executablePath: String
            if let override = profile.executablePathOverride, !override.isEmpty {
                executablePath = override
            } else if let resolved = executableResolver.resolveExecutable(named: provider.binaryName) {
                executablePath = resolved
            } else {
                throw AgentProcessError.missingExecutable(profile.executablePathOverride ?? provider.binaryName)
            }

            let argumentLines = profile.argumentLines
            let arguments: [String]
            if argumentLines.isEmpty {
                // Empty template — fall back to the catalog defaults so the
                // user can leave the template blank and still get a working
                // command.
                arguments = Self.defaultCommandArguments(
                    for: provider.identifier,
                    coordinationPrompt: coordinationPrompt,
                    projectPath: projectPath,
                    mode: mode
                )
            } else {
                arguments = argumentLines.map { line in
                    Self.applyPlaceholders(
                        in: line,
                        coordinationPrompt: coordinationPrompt,
                        projectPath: projectPath,
                        mode: mode,
                        providerID: provider.identifier
                    )
                }
            }

            return AgentCommand(
                providerID: provider.identifier,
                executablePath: executablePath,
                arguments: arguments,
                environment: profile.environment,
                workingDirectory: projectPath,
                requiresApproval: mode != .recommendOnly
            )
        }

        // Catalog default path.
        guard let executablePath = executableResolver.resolveExecutable(named: provider.binaryName) else {
            throw AgentProcessError.missingExecutable(provider.binaryName)
        }

        let arguments = Self.defaultCommandArguments(
            for: provider.identifier,
            coordinationPrompt: coordinationPrompt,
            projectPath: projectPath,
            mode: mode
        )
        return AgentCommand(
            providerID: provider.identifier,
            executablePath: executablePath,
            arguments: arguments,
            workingDirectory: projectPath,
            requiresApproval: mode != .recommendOnly
        )
    }

    /// Coordination prompt shared with every provider so each agent reads
    /// AgentNotes.md before acting.
    static func coordinationPrompt(prompt: String, mode: AgentExecutionMode) -> String {
        """
        Before working, read AgentNotes.md if it exists. Summarize active constraints, \
        identify concurrent work, and avoid conflicting edits. Mode: \(mode.label).

        \(prompt)
        """
    }

    /// Substitute `{{prompt}}`, `{{project}}`, `{{mode}}`, and
    /// `{{provider_id}}` placeholders. An unset project becomes the empty
    /// string so user templates can omit the path safely.
    static func applyPlaceholders(
        in line: String,
        coordinationPrompt: String,
        projectPath: String?,
        mode: AgentExecutionMode,
        providerID: String
    ) -> String {
        line
            .replacingOccurrences(of: "{{prompt}}", with: coordinationPrompt)
            .replacingOccurrences(of: "{{project}}", with: projectPath ?? "")
            .replacingOccurrences(of: "{{mode}}", with: mode.label)
            .replacingOccurrences(of: "{{provider_id}}", with: providerID)
    }

    /// Catalog-default argument templates for each provider in the seed
    /// catalog. These are best-guess starting points — users override them
    /// via the setup wizard's Command Profile editor when their installed
    /// CLI takes different flags.
    static func defaultCommandArguments(
        for providerID: String,
        coordinationPrompt: String,
        projectPath: String?,
        mode: AgentExecutionMode
    ) -> [String] {
        switch providerID {
        case "openai.codex":
            var arguments = ["exec", "--json"]
            if let projectPath { arguments += ["--cd", projectPath] }
            arguments.append(coordinationPrompt)
            return arguments

        case "anthropic.claude-code":
            var arguments = ["--print", "--output-format", "stream-json"]
            if let projectPath { arguments += ["--add-dir", projectPath] }
            arguments.append(coordinationPrompt)
            return arguments

        case "github.copilot-cli":
            return ["copilot", "-p", coordinationPrompt]

        case "google.gemini-cli":
            var arguments: [String] = []
            if let projectPath { arguments += ["--workspace", projectPath] }
            arguments += ["-p", coordinationPrompt]
            return arguments

        case "cursor.agent":
            var arguments = ["agent"]
            if let projectPath { arguments += ["--workspace", projectPath] }
            arguments += ["--prompt", coordinationPrompt]
            return arguments

        case "kiro.cli":
            var arguments = ["chat"]
            if let projectPath { arguments += ["--workspace", projectPath] }
            arguments += ["--prompt", coordinationPrompt]
            return arguments

        case "qwen.code":
            var arguments: [String] = []
            if let projectPath { arguments += ["--workspace", projectPath] }
            arguments += ["--prompt", coordinationPrompt]
            return arguments

        case "mistral.vibe":
            var arguments = ["chat"]
            if let projectPath { arguments += ["--workspace", projectPath] }
            arguments += ["--prompt", coordinationPrompt]
            return arguments

        case "opencode.cli":
            var arguments = ["run"]
            if let projectPath { arguments += ["--workspace", projectPath] }
            arguments.append(coordinationPrompt)
            return arguments

        case "deepseek.api":
            // DeepSeek has no first-party standalone CLI; the user is
            // expected to supply a custom command profile. We emit a
            // descriptive placeholder so the approval sheet's command
            // preview shows why nothing will run without configuration.
            return ["--note", "DeepSeek requires a custom command profile (configure via Provider Setup).", coordinationPrompt]

        default:
            return [coordinationPrompt]
        }
    }
}

protocol CLIExecutableResolving: Sendable {
    func resolveExecutable(named binaryName: String) -> String?
    func versionString(executablePath: String) async -> String?
}

struct CLIExecutableResolver: CLIExecutableResolving {
    func resolveExecutable(named binaryName: String) -> String? {
        guard !binaryName.isEmpty else { return nil }

        let fileManager = FileManager.default
        let environmentPaths = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let commonPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "\(home)/.local/bin",
            "\(home)/.npm-global/bin",
        ]

        for path in Array(Set(environmentPaths + commonPaths)) {
            let candidate = URL(fileURLWithPath: path).appendingPathComponent(binaryName).path
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    func versionString(executablePath: String) async -> String? {
        await withCheckedContinuation { continuation in
            Task.detached(priority: .utility) {
                let process = Process()
                let output = Pipe()
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = ["--version"]
                process.standardOutput = output
                process.standardError = output

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    let raw = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: raw?.isEmpty == false ? raw : nil)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

actor ProviderHealthMonitor {
    private var lastSnapshots: [String: ProviderHealthSnapshot] = [:]

    func probe(provider: AgentProviderSnapshot) async -> ProviderHealthSnapshot {
        // Route through the shared adapter factory so Foundation Models
        // probes go through `SystemLanguageModel.default.availability`
        // rather than the generic CLI binary resolver.
        let adapter = AgentAdapterFactory.makeAdapter(providerID: provider.identifier)
        let snapshot = await adapter.availability(for: provider)
        lastSnapshots[provider.identifier] = snapshot
        return snapshot
    }

    func cachedSnapshot(providerID: String) -> ProviderHealthSnapshot? {
        lastSnapshots[providerID]
    }
}

/// Runs an `AgentCommand` and emits a stream of process lifecycle events.
///
/// Implementations are intentionally `Sendable` and stateless so they can be
/// shared across the app and substituted in tests via dependency injection.
protocol AgentRunning: Sendable {
    func stream(command: AgentCommand) -> AsyncThrowingStream<AgentProcessEvent, Error>
}

/// Production runner that launches a real `Process` for the resolved CLI.
struct AgentProcessRunner: AgentRunning {
    init() {}

    func stream(command: AgentCommand) -> AsyncThrowingStream<AgentProcessEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                let process = Process()
                let standardOutput = Pipe()
                let standardError = Pipe()

                process.executableURL = URL(fileURLWithPath: command.executablePath)
                process.arguments = command.arguments
                process.environment = ProcessInfo.processInfo.environment.merging(command.environment) { _, new in new }
                if let workingDirectory = command.workingDirectory {
                    process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
                }
                process.standardOutput = standardOutput
                process.standardError = standardError

                do {
                    continuation.yield(.started(command: command.displayCommand))

                    let stdoutTask = Task {
                        for try await line in standardOutput.fileHandleForReading.bytes.lines {
                            continuation.yield(.standardOutput(line))
                        }
                    }

                    let stderrTask = Task {
                        for try await line in standardError.fileHandleForReading.bytes.lines {
                            continuation.yield(.standardError(line))
                        }
                    }

                    try process.run()
                    process.waitUntilExit()
                    try await stdoutTask.value
                    try await stderrTask.value
                    continuation.yield(.finished(exitCode: process.terminationStatus))
                    continuation.finish()
                } catch {
                    if process.isRunning {
                        process.terminate()
                    }
                    continuation.finish(throwing: AgentProcessError.launchFailed(error.localizedDescription))
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}

/// A scripted, fully synchronous-feeling runner used by tests and SwiftUI
/// previews. Each step yields after an optional simulated delay; the final
/// step controls whether the stream completes normally or throws.
///
/// The scripted runner intentionally does not touch `Process`, so it is safe
/// to use in unit tests without spawning child processes.
struct ScriptedAgentProcessRunner: AgentRunning {
    enum Step: Sendable {
        case stdout(String)
        case stderr(String)
        case finished(exitCode: Int32)
        case fail(AgentProcessError)
    }

    let providerID: String
    let steps: [Step]
    let perStepDelayNanoseconds: UInt64

    init(
        providerID: String = "scripted.fake",
        steps: [Step],
        perStepDelayNanoseconds: UInt64 = 0
    ) {
        self.providerID = providerID
        self.steps = steps
        self.perStepDelayNanoseconds = perStepDelayNanoseconds
    }

    func stream(command: AgentCommand) -> AsyncThrowingStream<AgentProcessEvent, Error> {
        let scriptedSteps = steps
        let delay = perStepDelayNanoseconds
        return AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.started(command: command.displayCommand))
                for step in scriptedSteps {
                    if Task.isCancelled {
                        continuation.finish()
                        return
                    }
                    if delay > 0 {
                        try? await Task.sleep(nanoseconds: delay)
                    }
                    switch step {
                    case .stdout(let line):
                        continuation.yield(.standardOutput(line))
                    case .stderr(let line):
                        continuation.yield(.standardError(line))
                    case .finished(let code):
                        continuation.yield(.finished(exitCode: code))
                        continuation.finish()
                        return
                    case .fail(let error):
                        continuation.finish(throwing: error)
                        return
                    }
                }
                // If the script did not include a `.finished` or `.fail`, close
                // the stream cleanly with exit code 0 so dispatchers don't hang.
                continuation.yield(.finished(exitCode: 0))
                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}
