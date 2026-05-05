//
//  GitCheckpoint.swift
//  Agenic Load-Balancer
//
//  Created by Claude on 5/5/26.
//
//  Phase 6: shells out to git for commit/push checkpoints after a
//  successful run in `.commitPushCheckpoint` mode. The protocol-based
//  design lets tests inject a stub instead of touching a real repository.
//

import Foundation

/// Outcome of a checkpoint attempt. `pushed` is best-effort: a commit can
/// succeed even when the push fails (no remote configured, auth issue),
/// so the dispatcher records both signals separately.
struct GitCheckpointResult: Sendable, Hashable {
    let sha: String
    let message: String
    let pushed: Bool
    let pushError: String?
}

enum GitCheckpointError: Error, Sendable, LocalizedError, Equatable {
    case gitNotFound
    case repositoryNotInitialized(String)
    case nothingToCommit
    case commitFailed(String)
    case revParseFailed(String)
    case unsupportedProjectRoot(String)

    var errorDescription: String? {
        switch self {
        case .gitNotFound: "git was not found on PATH."
        case .repositoryNotInitialized(let path): "No git repository at \(path)."
        case .nothingToCommit: "Nothing to commit — working tree is clean."
        case .commitFailed(let message): "git commit failed: \(message)"
        case .revParseFailed(let message): "git rev-parse failed: \(message)"
        case .unsupportedProjectRoot(let path): "Project root is not a directory: \(path)"
        }
    }
}

/// Shell-out façade so tests can inject a stub. All implementations must be
/// `Sendable` because the dispatcher holds the collaborator across actor
/// boundaries.
protocol GitCheckpointing: Sendable {
    func commit(in projectURL: URL, message: String, push: Bool) async throws -> GitCheckpointResult
}

/// Real implementation. Resolves a git executable, runs `git add -A`,
/// `git commit -m <message>`, captures HEAD SHA, and optionally `git push`.
actor GitCheckpointCoordinator: GitCheckpointing {
    private let resolver: CLIExecutableResolving

    init(resolver: CLIExecutableResolving = CLIExecutableResolver()) {
        self.resolver = resolver
    }

    func commit(in projectURL: URL, message: String, push: Bool) async throws -> GitCheckpointResult {
        let path = projectURL.path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw GitCheckpointError.unsupportedProjectRoot(path)
        }

        let gitPath = try resolveGitExecutable()
        try await ensureRepository(at: projectURL, gitPath: gitPath)

        // Stage everything.
        _ = try await runCapturing(args: ["add", "-A"], cwd: projectURL, gitPath: gitPath)

        // Attempt commit.
        let commitResult = try await runCapturing(args: ["commit", "-m", message], cwd: projectURL, gitPath: gitPath)
        if commitResult.exitCode != 0 {
            let combined = (commitResult.stdout + "\n" + commitResult.stderr).lowercased()
            if combined.contains("nothing to commit") || combined.contains("no changes added") {
                throw GitCheckpointError.nothingToCommit
            }
            throw GitCheckpointError.commitFailed(commitResult.stderr.isEmpty ? commitResult.stdout : commitResult.stderr)
        }

        // Capture HEAD SHA.
        let revResult = try await runCapturing(args: ["rev-parse", "HEAD"], cwd: projectURL, gitPath: gitPath)
        guard revResult.exitCode == 0 else {
            throw GitCheckpointError.revParseFailed(revResult.stderr.isEmpty ? revResult.stdout : revResult.stderr)
        }
        let sha = revResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        // Optionally push. Failures here don't fail the checkpoint — we just
        // record the message so the user can act on it.
        var pushed = false
        var pushError: String?
        if push {
            do {
                let pushResult = try await runCapturing(args: ["push"], cwd: projectURL, gitPath: gitPath)
                if pushResult.exitCode == 0 {
                    pushed = true
                } else {
                    pushError = pushResult.stderr.isEmpty ? pushResult.stdout : pushResult.stderr
                }
            } catch {
                pushError = error.localizedDescription
            }
        }

        return GitCheckpointResult(
            sha: sha,
            message: message,
            pushed: pushed,
            pushError: pushError
        )
    }

    private func resolveGitExecutable() throws -> String {
        if FileManager.default.isExecutableFile(atPath: "/usr/bin/git") {
            return "/usr/bin/git"
        }
        if let resolved = resolver.resolveExecutable(named: "git") {
            return resolved
        }
        throw GitCheckpointError.gitNotFound
    }

    private func ensureRepository(at url: URL, gitPath: String) async throws {
        let result = try await runCapturing(args: ["rev-parse", "--is-inside-work-tree"], cwd: url, gitPath: gitPath)
        if result.exitCode != 0 {
            throw GitCheckpointError.repositoryNotInitialized(url.path)
        }
    }

    private struct CommandResult: Sendable {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    private func runCapturing(args: [String], cwd: URL, gitPath: String) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.executableURL = URL(fileURLWithPath: gitPath)
                process.arguments = args
                process.currentDirectoryURL = cwd
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                process.environment = ProcessInfo.processInfo.environment

                do {
                    try process.run()
                    process.waitUntilExit()
                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let result = CommandResult(
                        stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                        stderr: String(data: stderrData, encoding: .utf8) ?? "",
                        exitCode: process.terminationStatus
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

/// Test-friendly stub. Returns the configured result on every call, ignoring
/// the project URL/message. Tracks invocations so tests can assert.
struct StubGitCheckpoint: GitCheckpointing {
    enum Behavior: Sendable {
        case succeed(sha: String, pushed: Bool, pushError: String? = nil)
        case fail(GitCheckpointError)
    }

    let behavior: Behavior

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    func commit(in projectURL: URL, message: String, push: Bool) async throws -> GitCheckpointResult {
        switch behavior {
        case .succeed(let sha, let pushed, let pushError):
            return GitCheckpointResult(
                sha: sha,
                message: message,
                pushed: pushed && push,
                pushError: pushError
            )
        case .fail(let error):
            throw error
        }
    }
}
