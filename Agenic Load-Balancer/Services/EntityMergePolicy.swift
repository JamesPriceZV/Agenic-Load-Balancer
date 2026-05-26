//
//  EntityMergePolicy.swift
//  Agenic Load-Balancer
//
//  Sprint Q.1: per-entity merge rules for the Conflict Center. The Sprint
//  E/K engine could only handle generic `appendAudit` commutativity and
//  Lamport-clock arbitration; everything else fell through to "requires
//  review". This module adds explicit field-level rules for the entities
//  that genuinely diverge in real two-Mac drills — provider profiles,
//  autonomy tasks, and run outcomes — so the dispatcher can offer a
//  deterministic merged payload for safe fields and a precise hard-
//  conflict marker (with the offending field name) for risky fields.
//
//  Policies are intentionally Sendable + value-typed. They never read
//  SwiftData and never mutate target entities; the engine still owns the
//  final write through `ConflictResolutionEngine.apply(action:to:using:)`.
//

import Foundation

/// How a single field on an entity payload should be reconciled when the
/// local and remote operations disagree.
enum FieldMergeRule: String, Sendable, Hashable, Codable {
    /// Pick whichever side is non-empty; if both are non-empty and equal
    /// it's a no-op, if both are non-empty and different it's a hard
    /// conflict. Use for descriptive text that the user fills in once.
    case preferNonEmpty
    /// Pick the side whose payload carries the newer Lamport clock. Use
    /// for status badges, version strings, and timestamps where the
    /// later observation should win.
    case preferLatest
    /// Treat the field as append-only: split each side on `\n`,
    /// deduplicate, sort, and rejoin. Use for `userFeedback`, comment
    /// trails, audit text, etc.
    case concatLines
    /// The field is immutable once written. If the two sides disagree
    /// it's a hard conflict and the engine must escalate to review.
    case immutableHardConflict
    /// Terminal-state-wins rule: if either side is in a terminal state
    /// (`succeeded`, `failed`, `cancelled`, `checkpointed`, `resolved`),
    /// that side wins. If both are terminal but disagree, hard conflict.
    /// Use for `status` fields driven by state machines.
    case stateMachineFavorTerminal
    /// User-rated value wins over AI-suggested or unrated. Use for
    /// `accuracyRating` so the human verdict never gets overwritten.
    case userRatedWinsOverInferred
}

/// Policy for one entity type. `fieldRules` is keyed by payload field
/// name; fields not in the dictionary fall through to the engine's
/// generic Lamport arbitration.
struct EntityMergePolicy: Sendable, Hashable {
    let entityType: String
    let fieldRules: [String: FieldMergeRule]
    /// When `true`, the engine should treat audit-trail fields on the
    /// payload (any key prefixed with `audit_`) as commutative even if
    /// they're not listed in `fieldRules`. Defaults to `true` because
    /// every entity carries audit metadata in Sprint K+ drills.
    let auditFieldsAreCommutative: Bool
}

/// Result of evaluating a policy. Mirrors `ConflictResolutionOutcome`
/// but carries an explicit list of fields that caused a hard conflict
/// so the engine can surface them in the Conflict Center inspector.
enum EntityMergeResult: Sendable, Equatable {
    case merged(payload: [String: String], explanation: String)
    case hardConflict(fields: [String], reason: String)
    case notApplicable
}

enum EntityMergePolicyRegistry {
    /// Canonical entity types the registry knows about. Add new entries
    /// as future entity classes start appearing in cross-machine drills.
    static let providerProfile = "AgentProviderProfile"
    static let autonomyTask = "AutonomyTaskRecord"
    static let runOutcome = "RunOutcomeRecord"

    /// Set of payload field keys that are always commutative regardless
    /// of the entity type they appear under (audit lines, history
    /// fragments, debug breadcrumbs). The engine still consults the
    /// per-entity policy first.
    static let universallyCommutativePrefixes: [String] = [
        "audit_",
        "history_",
        "note_",
    ]

    static func policy(for entityType: String) -> EntityMergePolicy? {
        switch entityType {
        case providerProfile:
            return EntityMergePolicy(
                entityType: providerProfile,
                fieldRules: [
                    // Descriptive fields the user fills in.
                    "capabilities": .preferNonEmpty,
                    "installCommand": .preferNonEmpty,
                    "verificationCommand": .preferNonEmpty,
                    "authMethods": .preferNonEmpty,
                    "quotaPolicySummary": .preferNonEmpty,
                    "safetyNotes": .preferNonEmpty,
                    // Most recent probe wins for state badges.
                    "installedState": .preferLatest,
                    "authState": .preferLatest,
                    "lastDetectedVersion": .preferLatest,
                    // Identity fields are immutable post-creation.
                    "identifier": .immutableHardConflict,
                    "providerFamily": .immutableHardConflict,
                    "binaryName": .immutableHardConflict,
                ],
                auditFieldsAreCommutative: true
            )
        case autonomyTask:
            return EntityMergePolicy(
                entityType: autonomyTask,
                fieldRules: [
                    "detail": .preferNonEmpty,
                    "validationCommand": .preferNonEmpty,
                    "assignedProviderID": .preferLatest,
                    "mode": .preferLatest,
                    "status": .stateMachineFavorTerminal,
                    "title": .preferNonEmpty,
                    "identifier": .immutableHardConflict,
                    "goalID": .immutableHardConflict,
                ],
                auditFieldsAreCommutative: true
            )
        case runOutcome:
            return EntityMergePolicy(
                entityType: runOutcome,
                fieldRules: [
                    "userFeedback": .concatLines,
                    "continuationSummary": .preferNonEmpty,
                    "continuationPrompt": .preferLatest,
                    "contextBudgetSummary": .preferLatest,
                    "aiOneLineDescription": .preferNonEmpty,
                    "accuracyRating": .userRatedWinsOverInferred,
                    "status": .stateMachineFavorTerminal,
                    "buildResult": .immutableHardConflict,
                    "identifier": .immutableHardConflict,
                    "runID": .immutableHardConflict,
                    "providerID": .immutableHardConflict,
                ],
                auditFieldsAreCommutative: true
            )
        default:
            return nil
        }
    }

    /// Set of accuracy-rating values that count as "user verdicts". When
    /// the user has rated the run, that side wins over any AI-suggested
    /// or unrated value on the other side. Kept here (not in the model
    /// enum) because the merge layer is the only thing that needs to
    /// distinguish "human said this" from "model suggested this".
    static let userRatedAccuracyValues: Set<String> = [
        "correct",
        "minorFixNeeded",
        "majorFixNeeded",
        "incorrect",
    ]

    /// Set of statuses that count as terminal. The terminal-wins rule
    /// uses this to decide which side of a state-machine field wins.
    static let terminalStatusValues: Set<String> = [
        "succeeded",
        "failed",
        "cancelled",
        "checkpointed",
        "resolved",
        "restorePlanned",
        "completed",
    ]
}

enum EntityMergePolicyEvaluator {
    /// Evaluate the policy against the two operation payloads. The
    /// returned result is consumed by `ConflictResolutionEngine.resolve`.
    static func evaluate(
        policy: EntityMergePolicy,
        local: OperationEnvelope,
        remote: OperationEnvelope
    ) -> EntityMergeResult {
        guard local.entityType == policy.entityType,
              remote.entityType == policy.entityType else {
            return .notApplicable
        }

        var merged: [String: String] = [:]
        var hardConflictFields: [String] = []
        var explanations: [String] = []

        let allKeys = Set(local.payload.keys).union(remote.payload.keys)
        for key in allKeys.sorted() {
            let leftValue = local.payload[key]
            let rightValue = remote.payload[key]
            let rule = effectiveRule(for: key, in: policy)

            switch (leftValue, rightValue) {
            case (nil, let value?), (let value?, nil):
                merged[key] = value
            case (let left?, let right?):
                if left == right {
                    merged[key] = left
                } else {
                    switch rule {
                    case .preferNonEmpty:
                        let leftTrim = left.trimmingCharacters(in: .whitespacesAndNewlines)
                        let rightTrim = right.trimmingCharacters(in: .whitespacesAndNewlines)
                        if leftTrim.isEmpty && !rightTrim.isEmpty {
                            merged[key] = right
                        } else if rightTrim.isEmpty && !leftTrim.isEmpty {
                            merged[key] = left
                        } else if leftTrim == rightTrim {
                            merged[key] = left
                        } else {
                            hardConflictFields.append(key)
                            merged[key] = preferLatest(left: left, right: right, local: local, remote: remote)
                        }
                    case .preferLatest:
                        merged[key] = preferLatest(left: left, right: right, local: local, remote: remote)
                        explanations.append("\(key): preferred latest Lamport-clock value.")
                    case .concatLines:
                        let combined = mergeLines(left: left, right: right)
                        merged[key] = combined
                        explanations.append("\(key): merged append-only lines.")
                    case .immutableHardConflict:
                        hardConflictFields.append(key)
                    case .stateMachineFavorTerminal:
                        let leftTerminal = EntityMergePolicyRegistry.terminalStatusValues.contains(left)
                        let rightTerminal = EntityMergePolicyRegistry.terminalStatusValues.contains(right)
                        if leftTerminal && !rightTerminal {
                            merged[key] = left
                            explanations.append("\(key): kept terminal local state '\(left)' over remote '\(right)'.")
                        } else if rightTerminal && !leftTerminal {
                            merged[key] = right
                            explanations.append("\(key): kept terminal remote state '\(right)' over local '\(left)'.")
                        } else if leftTerminal && rightTerminal {
                            hardConflictFields.append(key)
                        } else {
                            merged[key] = preferLatest(left: left, right: right, local: local, remote: remote)
                            explanations.append("\(key): preferred latest non-terminal state.")
                        }
                    case .userRatedWinsOverInferred:
                        let leftRated = EntityMergePolicyRegistry.userRatedAccuracyValues.contains(left)
                        let rightRated = EntityMergePolicyRegistry.userRatedAccuracyValues.contains(right)
                        if leftRated && !rightRated {
                            merged[key] = left
                            explanations.append("\(key): kept user rating '\(left)'.")
                        } else if rightRated && !leftRated {
                            merged[key] = right
                            explanations.append("\(key): kept user rating '\(right)'.")
                        } else if leftRated && rightRated {
                            hardConflictFields.append(key)
                        } else {
                            merged[key] = preferLatest(left: left, right: right, local: local, remote: remote)
                        }
                    }
                }
            default:
                continue
            }
        }

        if !hardConflictFields.isEmpty {
            return .hardConflict(
                fields: hardConflictFields,
                reason: "Hard conflict on \(hardConflictFields.count) field(s): \(hardConflictFields.joined(separator: ", "))."
            )
        }
        let explanation = explanations.isEmpty
            ? "All fields merged cleanly under the \(policy.entityType) policy."
            : explanations.joined(separator: " ")
        return .merged(payload: merged, explanation: explanation)
    }

    // MARK: - Helpers

    private static func effectiveRule(
        for key: String,
        in policy: EntityMergePolicy
    ) -> FieldMergeRule {
        if let explicit = policy.fieldRules[key] {
            return explicit
        }
        if policy.auditFieldsAreCommutative,
           EntityMergePolicyRegistry.universallyCommutativePrefixes.contains(where: { key.hasPrefix($0) }) {
            return .concatLines
        }
        // Anything not declared falls back to "latest Lamport wins" — the
        // engine's pre-Sprint-Q.1 default.
        return .preferLatest
    }

    private static func preferLatest(
        left: String,
        right: String,
        local: OperationEnvelope,
        remote: OperationEnvelope
    ) -> String {
        if local.lamportClock > remote.lamportClock { return left }
        if remote.lamportClock > local.lamportClock { return right }
        // Tied clocks: deterministic tie-break on machine ID so the
        // output is reproducible regardless of which side called first.
        return local.machineID <= remote.machineID ? left : right
    }

    private static func mergeLines(left: String, right: String) -> String {
        let pieces = (left + "\n" + right)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        let unique = Array(NSOrderedSet(array: pieces.sorted())) as? [String] ?? Array(Set(pieces)).sorted()
        return unique.joined(separator: "\n")
    }
}
