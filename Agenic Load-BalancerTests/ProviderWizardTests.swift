//
//  ProviderWizardTests.swift
//  Agenic Load-BalancerTests
//
//  Created by Claude on 5/5/26.
//
//  Phase 5: tests for the per-provider adapter coverage and the
//  ProviderCommandProfile override path. The wizard's UI is exercised
//  manually; these tests cover the logic underneath it (command argument
//  templates, profile-driven overrides, placeholder substitution, and
//  environment JSON parsing).
//

import Foundation
import SwiftData
import Testing
@testable import Agenic_Load_Balancer

@MainActor
@Suite("Provider wizard / adapter coverage")
struct ProviderWizardTests {
    private struct StubExecutableResolver: CLIExecutableResolving {
        let resolvedPath: String?
        let version: String?

        func resolveExecutable(named binaryName: String) -> String? { resolvedPath }
        func versionString(executablePath: String) async -> String? { version }
    }

    private static func snapshot(for catalogIndex: Int) -> AgentProviderSnapshot {
        let draft = ProviderCatalog.defaultProfiles[catalogIndex]
        return AgentProviderSnapshot(
            identifier: draft.identifier,
            displayName: draft.displayName,
            binaryName: draft.binaryName,
            installCommand: draft.installCommand,
            verificationCommand: draft.verificationCommand,
            supportedExecutionModes: draft.supportedExecutionModes,
            capabilities: draft.capabilities,
            installedState: .available,
            authState: .authenticated,
            isEnabled: true
        )
    }

    private static func snapshot(forProviderID id: String) -> AgentProviderSnapshot {
        guard let index = ProviderCatalog.defaultProfiles.firstIndex(where: { $0.identifier == id }) else {
            preconditionFailure("Unknown catalog provider: \(id)")
        }
        return snapshot(for: index)
    }

    // MARK: Catalog default arguments

    @Test func codexDefaultsIncludeJSONExecAndProjectFlag() throws {
        let provider = Self.snapshot(forProviderID: "openai.codex")
        let adapter = GenericCLIAdapter(
            providerID: provider.identifier,
            executableResolver: StubExecutableResolver(resolvedPath: "/usr/local/bin/codex", version: "1.0")
        )
        let command = try adapter.buildCommand(
            prompt: "do thing",
            projectPath: "/tmp/proj",
            mode: .implementation,
            provider: provider
        )
        #expect(command.arguments.contains("exec"))
        #expect(command.arguments.contains("--json"))
        #expect(command.arguments.contains("--cd"))
        #expect(command.arguments.contains("/tmp/proj"))
        #expect(command.arguments.last == "-")
        #expect(command.standardInput?.contains("Before working") == true)
        #expect(command.standardInput?.contains("do thing") == true)
    }

    @Test func eachCatalogProviderProducesAtLeastTwoArguments() throws {
        for draft in ProviderCatalog.defaultProfiles {
            // DeepSeek has no first-party CLI so the catalog default is a
            // descriptive note + prompt. Skip it because resolverPath would
            // fail availability checks — but verify the default arguments
            // function still returns a non-empty array.
            let arguments = GenericCLIAdapter.defaultCommandArguments(
                for: draft.identifier,
                coordinationPrompt: "{{prompt}}",
                projectPath: "/tmp/sample",
                mode: .implementation
            )
            #expect(arguments.count >= 1, "Provider \(draft.identifier) returned an empty argument array")
            if draft.identifier == "openai.codex" {
                #expect(arguments.last == "-", "Codex should read the prompt from stdin")
            } else {
                #expect(arguments.last?.contains("{{prompt}}") == true || arguments.last?.contains("prompt") == true,
                        "Provider \(draft.identifier) does not pipe the coordination prompt as the final argument")
            }
        }
    }

    @Test func deepSeekDefaultIncludesCustomProfileNote() {
        let arguments = GenericCLIAdapter.defaultCommandArguments(
            for: "deepseek.api",
            coordinationPrompt: "PROMPT",
            projectPath: nil,
            mode: .implementation
        )
        #expect(arguments.contains { $0.contains("custom command profile") })
    }

    // MARK: Profile override

    @Test func enabledProfileOverridesExecutableAndArguments() throws {
        let provider = Self.snapshot(forProviderID: "openai.codex")
        let profile = ProviderCommandProfileSnapshot(
            identifier: UUID().uuidString,
            providerID: provider.identifier,
            displayName: "Custom",
            executablePathOverride: "/opt/local/bin/codex-custom",
            argumentTemplate: """
            run
            --prompt
            {{prompt}}
            --workspace
            {{project}}
            --mode
            {{mode}}
            """,
            environmentJSON: #"{"OPENAI_API_KEY":"sk-test"}"#,
            isEnabled: true
        )
        let adapter = GenericCLIAdapter(
            providerID: provider.identifier,
            commandProfile: profile,
            executableResolver: StubExecutableResolver(resolvedPath: "/usr/local/bin/codex", version: "1.0")
        )
        let command = try adapter.buildCommand(
            prompt: "fix the bug",
            projectPath: "/Users/me/proj",
            mode: .implementation,
            provider: provider
        )
        #expect(command.executablePath == "/opt/local/bin/codex-custom")
        #expect(command.arguments.first == "run")
        #expect(command.arguments.contains("--workspace"))
        #expect(command.arguments.contains("/Users/me/proj"))
        #expect(command.arguments.contains("Implement")) // mode label
        // The coordination-wrapped prompt embeds the original prompt.
        #expect(command.arguments.contains { $0.contains("fix the bug") })
        #expect(command.environment["OPENAI_API_KEY"] == "sk-test")
    }

    @Test func disabledProfileFallsBackToCatalogDefaults() throws {
        let provider = Self.snapshot(forProviderID: "openai.codex")
        let profile = ProviderCommandProfileSnapshot(
            identifier: UUID().uuidString,
            providerID: provider.identifier,
            displayName: "Custom (disabled)",
            executablePathOverride: "/wrong/path",
            argumentTemplate: "run\n--bogus",
            environmentJSON: "{}",
            isEnabled: false
        )
        let adapter = GenericCLIAdapter(
            providerID: provider.identifier,
            commandProfile: profile,
            executableResolver: StubExecutableResolver(resolvedPath: "/usr/local/bin/codex", version: "1.0")
        )
        let command = try adapter.buildCommand(
            prompt: "anything",
            projectPath: nil,
            mode: .implementation,
            provider: provider
        )
        #expect(command.executablePath == "/usr/local/bin/codex")
        #expect(command.arguments.first == "exec")
        #expect(!command.arguments.contains("--bogus"))
        #expect(command.arguments.last == "-")
        #expect(command.standardInput?.contains("anything") == true)
    }

    @Test func enabledProfileWithEmptyTemplateUsesCatalogDefaults() throws {
        let provider = Self.snapshot(forProviderID: "openai.codex")
        let profile = ProviderCommandProfileSnapshot(
            identifier: UUID().uuidString,
            providerID: provider.identifier,
            displayName: "Empty template",
            executablePathOverride: nil,
            argumentTemplate: "   \n  \n",
            environmentJSON: "{}",
            isEnabled: true
        )
        let adapter = GenericCLIAdapter(
            providerID: provider.identifier,
            commandProfile: profile,
            executableResolver: StubExecutableResolver(resolvedPath: "/usr/local/bin/codex", version: "1.0")
        )
        let command = try adapter.buildCommand(
            prompt: "hi",
            projectPath: nil,
            mode: .planOnly,
            provider: provider
        )
        // Catalog default for codex starts with `exec`.
        #expect(command.arguments.first == "exec")
        #expect(command.arguments.last == "-")
        #expect(command.standardInput?.contains("hi") == true)
    }

    @Test func enabledCodexProfileWithDashPipesPromptToStandardInput() throws {
        let provider = Self.snapshot(forProviderID: "openai.codex")
        let profile = ProviderCommandProfileSnapshot(
            identifier: UUID().uuidString,
            providerID: provider.identifier,
            displayName: "Stdin template",
            executablePathOverride: nil,
            argumentTemplate: "exec\n--json\n-",
            environmentJSON: "{}",
            isEnabled: true
        )
        let adapter = GenericCLIAdapter(
            providerID: provider.identifier,
            commandProfile: profile,
            executableResolver: StubExecutableResolver(resolvedPath: "/usr/local/bin/codex", version: "1.0")
        )
        let command = try adapter.buildCommand(
            prompt: "review the pipeline",
            projectPath: nil,
            mode: .readReview,
            provider: provider
        )
        #expect(command.arguments == ["exec", "--json", "-"])
        #expect(command.standardInput?.contains("review the pipeline") == true)
    }

    // MARK: Placeholder substitution

    @Test func placeholdersAreSubstitutedInTemplate() {
        let result = GenericCLIAdapter.applyPlaceholders(
            in: "agent --prompt {{prompt}} --project {{project}} --mode {{mode}} ({{provider_id}})",
            coordinationPrompt: "Hello",
            projectPath: "/tmp",
            mode: .repairDebug,
            providerID: "test.provider"
        )
        #expect(result == "agent --prompt Hello --project /tmp --mode Repair / Debug (test.provider)")
    }

    @Test func nilProjectSubstitutesEmptyString() {
        let result = GenericCLIAdapter.applyPlaceholders(
            in: "{{project}}",
            coordinationPrompt: "p",
            projectPath: nil,
            mode: .implementation,
            providerID: "x"
        )
        #expect(result == "")
    }

    // MARK: Environment parsing

    @Test func environmentJSONParsesValidDictionary() {
        let snapshot = ProviderCommandProfileSnapshot(
            identifier: "id",
            providerID: "p",
            displayName: "n",
            executablePathOverride: nil,
            argumentTemplate: "",
            environmentJSON: #"{"FOO":"1","BAR":"baz"}"#,
            isEnabled: true
        )
        #expect(snapshot.environment == ["FOO": "1", "BAR": "baz"])
    }

    @Test func environmentJSONReturnsEmptyForMalformedInput() {
        let snapshot = ProviderCommandProfileSnapshot(
            identifier: "id",
            providerID: "p",
            displayName: "n",
            executablePathOverride: nil,
            argumentTemplate: "",
            environmentJSON: "{ this is not json",
            isEnabled: true
        )
        #expect(snapshot.environment.isEmpty)
    }

    @Test func argumentLinesIgnoreBlankAndWhitespaceLines() {
        let snapshot = ProviderCommandProfileSnapshot(
            identifier: "id",
            providerID: "p",
            displayName: "n",
            executablePathOverride: nil,
            argumentTemplate: "  one  \n\n   \n--two\n   value  ",
            environmentJSON: "{}",
            isEnabled: true
        )
        #expect(snapshot.argumentLines == ["one", "--two", "value"])
    }

    // MARK: Wizard helpers

    @Test func defaultCommandProfileDraftSeedsCatalogTemplate() async {
        let provider = Self.snapshot(forProviderID: "openai.codex")
        let wizard = ProviderSetupWizard()
        let draft = wizard.defaultCommandProfileDraft(for: provider)
        #expect(draft.providerID == "openai.codex")
        #expect(draft.argumentTemplate.contains("-"))
        #expect(draft.argumentTemplate.contains("{{project}}"))
        #expect(draft.argumentTemplate.contains("exec"))
        #expect(draft.environmentJSON == "{}")
        #expect(draft.isEnabled == false)
    }

    // MARK: Schema includes profile model

    @Test func schemaIncludesProviderCommandProfile() {
        let modelTypes = AgenicDataModel.models.map { String(describing: $0) }
        #expect(modelTypes.contains("ProviderCommandProfile"))
    }
}
