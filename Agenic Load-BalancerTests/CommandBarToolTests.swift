//
//  CommandBarToolTests.swift
//  Agenic Load-BalancerTests
//
//  Phase 7.3 command-bar tool and fallback tests.
//

import Foundation
import Testing
@testable import Agenic_Load_Balancer

@Suite("Phase 7.3 command tools")
struct CommandBarToolTests {
    private static var context: CommandBarContext {
        CommandBarContext(
            prompt: "Rank agents for the build",
            mode: .testBuild,
            providers: [
                AgentProviderSnapshot(
                    identifier: "openai.codex",
                    displayName: "Codex",
                    binaryName: "codex",
                    installCommand: "brew install codex",
                    verificationCommand: "codex --version",
                    supportedExecutionModes: AgentExecutionMode.allCases.map(\.rawValue).joined(separator: ","),
                    capabilities: "code-editing,debugging,local-workspace",
                    installedState: .available,
                    authState: .authenticated,
                    isEnabled: true
                ),
            ]
        )
    }

    @Test func deterministicFallbackRanksWhenFoundationModelsUnavailable() async {
        let output = await NaturalLanguageCommandBarModel.deterministicFallback(
            prompt: "rank agents",
            context: Self.context,
            executor: CommandBarActionExecutor(),
            unavailableReason: "Apple Intelligence disabled"
        )

        #expect(output.contains("Foundation Models unavailable"))
        #expect(output.contains("Ranked 1 agent"))
    }

    @Test func deterministicFallbackCreatesApprovalDraftForDispatch() async {
        let output = await NaturalLanguageCommandBarModel.deterministicFallback(
            prompt: "dispatch this run",
            context: Self.context,
            executor: CommandBarActionExecutor(),
            unavailableReason: "Apple Intelligence disabled"
        )

        #expect(output.contains("Approve dispatch to Codex"))
        #expect(output.contains("Approval required: dispatch:openai.codex:"))
    }

    @Test func toolDescriptionsMakeMutatingActionsDraftOnly() {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let dispatch = DispatchRunTool(
                executor: CommandBarActionExecutor(),
                contextProvider: { Self.context }
            )
            let snapshot = CreateSnapshotTool(executor: CommandBarActionExecutor())

            #expect(dispatch.description.contains("does not start"))
            #expect(snapshot.description.contains("approval"))
        }
        #endif
    }
}
