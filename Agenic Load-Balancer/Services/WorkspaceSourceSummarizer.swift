//
//  WorkspaceSourceSummarizer.swift
//  Agenic Load-Balancer
//
//  Sprint O.1: deterministic, allowlist-based source-file summarization
//  used when preparing a continuation prompt for a long run. Reads at most
//  `maxFileCount` recently modified source files inside the workspace and
//  produces head/tail excerpts bounded by a total character budget.
//
//  This summarizer is intentionally read-only and Sendable. It never
//  mutates the workspace, never expands hidden directories, never follows
//  symlinks past `projectRoot`, and never reads anything outside
//  `projectRoot`. Binary files, oversized files, and files outside the
//  allowlist are skipped so a malicious workspace cannot inflate the
//  continuation prompt.
//

import Foundation

/// One excerpt of a workspace file, ready to be embedded in a prompt.
struct WorkspaceSourceExcerpt: Sendable, Hashable {
    let relativePath: String
    let totalLineCount: Int
    let excerpt: String
    let isTruncated: Bool
    let estimatedTokens: Int
}

/// Aggregate context used in the continuation prompt body.
struct WorkspaceSourceContext: Sendable, Hashable {
    let projectRootPath: String
    let excerpts: [WorkspaceSourceExcerpt]
    let totalEstimatedTokens: Int
    let totalFilesScanned: Int
    /// Already-formatted prompt fragment with one section per excerpt and a
    /// final "[no source files matched]" note when applicable. Empty string
    /// when there is no project root at all.
    let formattedPromptFragment: String
}

enum WorkspaceSourceSummarizer {
    /// Files we will consider for excerpting. Extensions only — anything
    /// outside the list is skipped so binaries, archives, and signed
    /// payloads never reach the continuation prompt.
    static let allowedExtensions: Set<String> = [
        "swift", "m", "mm", "h", "hpp", "c", "cpp",
        "js", "ts", "tsx", "jsx",
        "py", "rb", "go", "rs",
        "json", "yaml", "yml", "toml",
        "md", "markdown",
        "sh", "bash", "zsh",
        "plist",
    ]

    /// Directories we never descend into when scanning a workspace.
    static let skippedDirectories: Set<String> = [
        ".git", ".build", "build", ".swiftpm", "DerivedData",
        "node_modules", "Pods", "Carthage", ".gradle", "target",
        ".venv", "venv", "__pycache__",
        ".DS_Store",
    ]

    /// Maximum bytes any single file may be before we skip it (binary
    /// protection + memory cap). 256 KiB is comfortable for source files
    /// and refuses generated payloads.
    static let perFileByteCap: Int = 256 * 1024

    /// Build a deterministic source context for the given project root.
    /// `targetTotalTokens` is a soft cap; the function stops adding new
    /// excerpts once the running token estimate exceeds the cap.
    static func summarize(
        projectRootPath: String?,
        targetTotalTokens: Int,
        maxFileCount: Int = 6,
        fileManager: FileManager = .default,
        clock: @Sendable () -> Date = Date.init
    ) -> WorkspaceSourceContext {
        guard let projectRootPath, !projectRootPath.isEmpty else {
            return WorkspaceSourceContext(
                projectRootPath: "",
                excerpts: [],
                totalEstimatedTokens: 0,
                totalFilesScanned: 0,
                formattedPromptFragment: ""
            )
        }
        let rootURL = URL(fileURLWithPath: projectRootPath, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return WorkspaceSourceContext(
                projectRootPath: projectRootPath,
                excerpts: [],
                totalEstimatedTokens: 0,
                totalFilesScanned: 0,
                formattedPromptFragment: "[workspace path not found: \(projectRootPath)]"
            )
        }

        let scanned = scan(
            rootURL: rootURL,
            fileManager: fileManager
        )

        // Most-recently-modified first, stable on equal mtimes by path so
        // the prompt is reproducible across runs on the same workspace.
        let ordered = scanned.sorted { lhs, rhs in
            if lhs.modificationDate == rhs.modificationDate {
                return lhs.url.path < rhs.url.path
            }
            return lhs.modificationDate > rhs.modificationDate
        }

        var excerpts: [WorkspaceSourceExcerpt] = []
        var runningTokens = 0
        let safeBudget = max(256, targetTotalTokens)
        // `clock` is reserved for future expiry / freshness gating; invoke
        // it once so callers that pass a deterministic clock can observe
        // that the summarizer ran without it becoming an unused warning.
        _ = clock()

        for candidate in ordered {
            guard excerpts.count < maxFileCount else { break }
            guard runningTokens < safeBudget else { break }
            guard candidate.fileSize <= perFileByteCap else { continue }
            guard let excerpt = makeExcerpt(
                for: candidate,
                rootURL: rootURL,
                targetTokens: min(900, max(192, (safeBudget - runningTokens) / 2))
            ) else { continue }
            excerpts.append(excerpt)
            runningTokens += excerpt.estimatedTokens
        }

        let fragment = formatFragment(
            rootURL: rootURL,
            excerpts: excerpts
        )

        return WorkspaceSourceContext(
            projectRootPath: projectRootPath,
            excerpts: excerpts,
            totalEstimatedTokens: runningTokens,
            totalFilesScanned: scanned.count,
            formattedPromptFragment: fragment
        )
    }

    // MARK: - Internal

    private struct Candidate: Sendable {
        let url: URL
        let modificationDate: Date
        let fileSize: Int
    }

    private static func scan(rootURL: URL, fileManager: FileManager) -> [Candidate] {
        var results: [Candidate] = []
        let resourceKeys: [URLResourceKey] = [
            .isRegularFileKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .contentModificationDateKey,
            .fileSizeKey,
            .nameKey,
        ]
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        let rootPath = rootURL.standardizedFileURL.path
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(resourceKeys)) else {
                continue
            }
            if values.isSymbolicLink == true {
                continue
            }
            let name = values.name ?? fileURL.lastPathComponent
            if values.isDirectory == true {
                if skippedDirectories.contains(name) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values.isRegularFile == true else { continue }
            let standardized = fileURL.standardizedFileURL.path
            if !standardized.hasPrefix(rootPath) {
                // Symlink chain landed us outside the root — refuse.
                continue
            }
            let ext = fileURL.pathExtension.lowercased()
            guard allowedExtensions.contains(ext) else { continue }
            let mtime = values.contentModificationDate ?? .distantPast
            let size = values.fileSize ?? 0
            results.append(Candidate(
                url: fileURL,
                modificationDate: mtime,
                fileSize: size
            ))
        }
        return results
    }

    private static func makeExcerpt(
        for candidate: Candidate,
        rootURL: URL,
        targetTokens: Int
    ) -> WorkspaceSourceExcerpt? {
        guard let data = try? Data(contentsOf: candidate.url) else { return nil }
        guard let text = String(data: data, encoding: .utf8) else {
            // Skip non-UTF8 (likely binary) files even when the extension
            // suggests text.
            return nil
        }
        let trimmed = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
        let totalLines = lines.count
        let relative = relativePath(of: candidate.url, against: rootURL)

        let targetCharacters = max(384, targetTokens * 4)
        if trimmed.count <= targetCharacters {
            let estimate = TokenBudgetEstimator.estimateTokens(in: trimmed)
            return WorkspaceSourceExcerpt(
                relativePath: relative,
                totalLineCount: totalLines,
                excerpt: trimmed,
                isTruncated: false,
                estimatedTokens: estimate
            )
        }

        // Head + tail excerpt with an explicit middle-omitted marker so the
        // agent can tell content was elided rather than guessing.
        let headCharacters = max(256, Int(Double(targetCharacters) * 0.55))
        let tailCharacters = max(160, targetCharacters - headCharacters - 96)
        let head = String(trimmed.prefix(headCharacters))
        let tail = String(trimmed.suffix(tailCharacters))
        let excerptBody = """
        \(head)
        ...[middle omitted for continuation budget]...
        \(tail)
        """
        let estimate = TokenBudgetEstimator.estimateTokens(in: excerptBody)
        return WorkspaceSourceExcerpt(
            relativePath: relative,
            totalLineCount: totalLines,
            excerpt: excerptBody,
            isTruncated: true,
            estimatedTokens: estimate
        )
    }

    private static func relativePath(of fileURL: URL, against rootURL: URL) -> String {
        let standardized = fileURL.standardizedFileURL.path
        let rootPath = rootURL.standardizedFileURL.path
        if standardized.hasPrefix(rootPath + "/") {
            return String(standardized.dropFirst(rootPath.count + 1))
        }
        if standardized == rootPath {
            return fileURL.lastPathComponent
        }
        return standardized
    }

    private static func formatFragment(rootURL: URL, excerpts: [WorkspaceSourceExcerpt]) -> String {
        guard !excerpts.isEmpty else {
            return "[no source files matched the continuation allowlist in \(rootURL.lastPathComponent)]"
        }
        var sections: [String] = []
        sections.append("Recent workspace excerpts (head/tail only, total \(excerpts.count) file(s)):")
        for excerpt in excerpts {
            let truncationNote = excerpt.isTruncated ? " (truncated)" : ""
            sections.append("""
            --- \(excerpt.relativePath) (\(excerpt.totalLineCount) line(s)\(truncationNote)) ---
            \(excerpt.excerpt)
            """)
        }
        return sections.joined(separator: "\n")
    }
}
