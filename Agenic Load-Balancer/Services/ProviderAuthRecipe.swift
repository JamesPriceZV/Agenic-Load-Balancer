//
//  ProviderAuthRecipe.swift
//  Agenic Load-Balancer
//
//  Provider-specific authentication guidance for the setup wizard.
//

import Foundation

struct ProviderAuthRecipe: Sendable, Hashable {
    struct Command: Sendable, Hashable, Identifiable {
        var id: String { command }
        let title: String
        let command: String
        let detail: String
    }

    let providerID: String
    let primaryMethod: String
    let billingBoundary: String
    let accountLoginCommands: [Command]
    let authProbeCommands: [Command]
    let apiKeyEnvironmentVariables: [String]
    let directOAuthSupported: Bool
    let directOAuthNote: String
    let docsURL: String
    let notes: [String]

    var supportsAccountLogin: Bool {
        !accountLoginCommands.isEmpty
    }

    var supportsAPIKey: Bool {
        !apiKeyEnvironmentVariables.isEmpty || primaryMethod.localizedCaseInsensitiveContains("API")
    }

    static func recipe(for providerID: String) -> ProviderAuthRecipe {
        switch providerID {
        case "openai.codex":
            return ProviderAuthRecipe(
                providerID: providerID,
                primaryMethod: "ChatGPT browser sign-in or OpenAI API key",
                billingBoundary: "ChatGPT sign-in and API-key billing are distinct Codex CLI modes; avoid unintentional API-key fallback when subscription billing is intended.",
                accountLoginCommands: [
                    .init(title: "Sign in with ChatGPT", command: "codex login", detail: "Official Codex CLI flow links ChatGPT sign-in to local credentials."),
                ],
                authProbeCommands: [
                    .init(title: "Check CLI", command: "codex --version", detail: "Version probe only; run a small `codex exec` after login to verify account routing."),
                ],
                apiKeyEnvironmentVariables: ["OPENAI_API_KEY"],
                directOAuthSupported: false,
                directOAuthNote: "Codex owns the browser/device login flow. Use the CLI login command instead of pasting a raw OAuth authorize URL.",
                docsURL: "https://help.openai.com/en/articles/11381614-codex-cli-and-sign-in-withgpt",
                notes: [
                    "Use `codex login` for ChatGPT sign-in.",
                    "Use API-key mode only when usage-based API billing is intended.",
                ]
            )

        case "anthropic.claude-code":
            return ProviderAuthRecipe(
                providerID: providerID,
                primaryMethod: "Claude account login, Anthropic API key, Bedrock, or Vertex",
                billingBoundary: "Claude account/subscription auth, Anthropic API keys, Bedrock, and Vertex are separate billing and policy lanes.",
                accountLoginCommands: [
                    .init(title: "Open Claude Code login", command: "claude", detail: "Start Claude Code and choose the Claude.ai login flow when prompted."),
                    .init(title: "Doctor", command: "claude doctor", detail: "Check installation and auth setup."),
                ],
                authProbeCommands: [
                    .init(title: "Check CLI", command: "claude --version", detail: "Verifies the installed CLI."),
                ],
                apiKeyEnvironmentVariables: ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL"],
                directOAuthSupported: false,
                directOAuthNote: "Claude Code owns its login flow and cloud-provider auth. Use the CLI flow or environment-backed provider config.",
                docsURL: "https://docs.anthropic.com/en/docs/claude-code/getting-started",
                notes: [
                    "Claude Code documents Claude.ai credentials, Anthropic API credentials, Bedrock Auth, and Vertex Auth.",
                    "DeepSeek Anthropic-compatible routing uses ANTHROPIC_BASE_URL plus ANTHROPIC_AUTH_TOKEN.",
                ]
            )

        case "github.copilot-cli":
            return ProviderAuthRecipe(
                providerID: providerID,
                primaryMethod: "Copilot OAuth device flow, supported GitHub tokens, or GitHub CLI fallback",
                billingBoundary: "Copilot subscription auth unlocks GitHub-hosted features; BYOK/provider API keys can bypass GitHub auth but do not unlock delegated GitHub features.",
                accountLoginCommands: [
                    .init(title: "Copilot OAuth", command: "copilot login", detail: "Starts the official device-code browser login."),
                    .init(title: "GitHub CLI fallback", command: "gh auth login", detail: "Authenticates gh so Copilot CLI can use it as a fallback."),
                ],
                authProbeCommands: [
                    .init(title: "Copilot help", command: "copilot --help", detail: "Checks a standalone Copilot CLI install."),
                    .init(title: "GitHub auth status", command: "gh auth status", detail: "Checks GitHub CLI fallback auth."),
                ],
                apiKeyEnvironmentVariables: ["COPILOT_GITHUB_TOKEN", "GH_TOKEN", "GITHUB_TOKEN", "COPILOT_PROVIDER_API_KEY"],
                directOAuthSupported: false,
                directOAuthNote: "Copilot CLI uses its own OAuth device-code browser flow; the app should not invent a provider authorize URL.",
                docsURL: "https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/authenticate-copilot-cli",
                notes: [
                    "Environment tokens override stored OAuth tokens.",
                    "Classic ghp_ tokens are not accepted for Copilot CLI auth.",
                ]
            )

        case "google.gemini-cli":
            return ProviderAuthRecipe(
                providerID: providerID,
                primaryMethod: "Google account browser sign-in, Gemini API key, or Vertex AI",
                billingBoundary: "Google account, Gemini API key, and Vertex AI are distinct auth and quota paths.",
                accountLoginCommands: [
                    .init(title: "Start Gemini auth", command: "gemini", detail: "Launch Gemini CLI and choose Sign in with Google or another auth method."),
                    .init(title: "Switch auth method", command: "gemini", detail: "Inside Gemini CLI, run /auth to change authentication method."),
                ],
                authProbeCommands: [
                    .init(title: "Check CLI", command: "gemini --version", detail: "Verifies the installed CLI."),
                    .init(title: "Stats", command: "gemini", detail: "Inside Gemini CLI, run /stats model to inspect session usage and quota."),
                ],
                apiKeyEnvironmentVariables: ["GEMINI_API_KEY", "GOOGLE_API_KEY"],
                directOAuthSupported: false,
                directOAuthNote: "Gemini CLI owns the Google sign-in browser flow and project linking.",
                docsURL: "https://github.com/google-gemini/gemini-cli/blob/main/docs/get-started/index.md",
                notes: [
                    "Existing GEMINI_API_KEY values can alter the auth path for a project.",
                    "Vertex AI auth should be treated as a separate enterprise lane.",
                ]
            )

        case "cursor.agent":
            return ProviderAuthRecipe(
                providerID: providerID,
                primaryMethod: "Cursor browser login or Cursor API key",
                billingBoundary: "Browser login uses the Cursor account plan; API-key mode is a separate automation/API lane.",
                accountLoginCommands: [
                    .init(title: "Cursor browser login", command: "cursor-agent login", detail: "Opens the default browser and stores Cursor credentials locally."),
                ],
                authProbeCommands: [
                    .init(title: "Status", command: "cursor-agent status", detail: "Checks Cursor account auth and endpoint state."),
                    .init(title: "Check CLI", command: "cursor-agent --version", detail: "Verifies the installed CLI."),
                ],
                apiKeyEnvironmentVariables: ["CURSOR_API_KEY"],
                directOAuthSupported: false,
                directOAuthNote: "Cursor Agent exposes its own browser login command; use that instead of a manual ASWebAuthenticationSession URL.",
                docsURL: "https://docs.cursor.com/en/cli/reference/authentication",
                notes: [
                    "The browser flow is the recommended interactive path.",
                    "API keys are intended for automation and CI/CD.",
                ]
            )

        case "kiro.cli":
            return ProviderAuthRecipe(
                providerID: providerID,
                primaryMethod: "Kiro/Amazon Q Builder ID or IAM Identity Center",
                billingBoundary: "Builder ID Free/Pro and IAM Identity Center Pro subscriptions have different limits and organization policy behavior.",
                accountLoginCommands: [
                    .init(title: "Kiro login", command: "kiro login", detail: "Use when Kiro CLI is installed and exposes its login command."),
                    .init(title: "Amazon Q login", command: "q login", detail: "Fallback path for legacy Amazon Q Developer CLI installs."),
                ],
                authProbeCommands: [
                    .init(title: "Check Kiro", command: "kiro --version", detail: "Verifies Kiro CLI."),
                    .init(title: "Check Amazon Q", command: "q --version", detail: "Verifies compatible Amazon Q CLI."),
                ],
                apiKeyEnvironmentVariables: ["AWS_PROFILE", "AWS_REGION"],
                directOAuthSupported: false,
                directOAuthNote: "AWS/Kiro identity flows are managed by the provider CLI and AWS identity center. Do not collect raw OAuth URLs.",
                docsURL: "https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/getting-started-builderid.html",
                notes: [
                    "Builder ID is for individual IDE/terminal use.",
                    "IAM Identity Center is the right lane for managed workforce identities.",
                ]
            )

        case "qwen.code":
            return ProviderAuthRecipe(
                providerID: providerID,
                primaryMethod: "Alibaba Cloud Coding Plan or API key",
                billingBoundary: "Qwen OAuth free tier was discontinued on 2026-04-15; Coding Plan and API-key providers are now the supported billing lanes.",
                accountLoginCommands: [
                    .init(title: "Configure auth", command: "qwen", detail: "Start Qwen Code and run /auth to choose Coding Plan or API-key provider."),
                ],
                authProbeCommands: [
                    .init(title: "Check CLI", command: "qwen --version", detail: "Verifies the installed CLI."),
                ],
                apiKeyEnvironmentVariables: ["DASHSCOPE_API_KEY", "OPENAI_API_KEY", "OPENROUTER_API_KEY"],
                directOAuthSupported: false,
                directOAuthNote: "Do not offer Qwen OAuth as a live option; official Qwen Code docs say it has been discontinued.",
                docsURL: "https://github.com/QwenLM/qwen-code",
                notes: [
                    "Use `qwen` then /auth to reconfigure.",
                    "Prefer modelProviders plus envKey in ~/.qwen/settings.json instead of hardcoding secrets.",
                ]
            )

        case "mistral.vibe":
            return ProviderAuthRecipe(
                providerID: providerID,
                primaryMethod: "Codestral/Mistral API key",
                billingBoundary: "Le Chat Pro Vibe budget and pay-as-you-go Studio API usage are distinct billing lanes.",
                accountLoginCommands: [
                    .init(title: "Interactive setup", command: "vibe --setup", detail: "Configures API key storage for Mistral Vibe."),
                ],
                authProbeCommands: [
                    .init(title: "Check CLI", command: "vibe --version", detail: "Verifies the installed CLI."),
                ],
                apiKeyEnvironmentVariables: ["MISTRAL_API_KEY", "OPENROUTER_API_KEY"],
                directOAuthSupported: false,
                directOAuthNote: "Mistral Vibe currently documents API-key setup, not an app-managed OAuth callback.",
                docsURL: "https://docs.mistral.ai/mistral-vibe/terminal/configuration",
                notes: [
                    "Mistral Vibe stores API keys under ~/.vibe/.env when configured interactively.",
                    "Environment variables take precedence over the .env file.",
                ]
            )

        case "opencode.cli":
            return ProviderAuthRecipe(
                providerID: providerID,
                primaryMethod: "OpenCode provider connection or provider API key",
                billingBoundary: "OpenCode brokers auth to the selected model provider; subscription/OAuth and API-key costs depend on that provider.",
                accountLoginCommands: [
                    .init(title: "Provider login", command: "opencode auth login", detail: "Configure provider credentials from the official provider list."),
                    .init(title: "TUI connect", command: "opencode", detail: "Inside OpenCode, run /connect to add providers such as GitHub Copilot or DeepSeek."),
                ],
                authProbeCommands: [
                    .init(title: "List auth", command: "opencode auth list", detail: "Shows configured OpenCode credentials."),
                    .init(title: "Check CLI", command: "opencode --version", detail: "Verifies the installed CLI."),
                ],
                apiKeyEnvironmentVariables: ["OPENAI_API_KEY", "ANTHROPIC_API_KEY", "DEEPSEEK_API_KEY", "AWS_PROFILE"],
                directOAuthSupported: false,
                directOAuthNote: "OpenCode handles provider connection and device/login flows inside its CLI/TUI.",
                docsURL: "https://opencode.ai/docs/cli/",
                notes: [
                    "Use /connect for providers with account/device login.",
                    "Use `opencode auth list` to verify credential state.",
                ]
            )

        case "apple.foundation-models":
            return ProviderAuthRecipe(
                providerID: providerID,
                primaryMethod: "Local Apple Intelligence availability",
                billingBoundary: "On-device Foundation Models do not use provider billing or API keys.",
                accountLoginCommands: [],
                authProbeCommands: [
                    .init(title: "In-app availability probe", command: "SystemLanguageModel.default.availability", detail: "The app checks Foundation Models availability in process."),
                ],
                apiKeyEnvironmentVariables: [],
                directOAuthSupported: false,
                directOAuthNote: "No browser login is required. Enable Apple Intelligence in System Settings.",
                docsURL: "https://developer.apple.com/documentation/foundationmodels",
                notes: [
                    "Runs on-device when Apple Intelligence is available.",
                    "Availability can vary by hardware, locale, account, and system settings.",
                ]
            )

        case "xcodebuildmcp.source":
            return ProviderAuthRecipe(
                providerID: providerID,
                primaryMethod: "Local XcodeBuildMCP connector and Xcode toolchain",
                billingBoundary: "No API or subscription billing is involved; XcodeBuildMCP executes local build/test/debug tooling through the configured MCP connector.",
                accountLoginCommands: [],
                authProbeCommands: [
                    .init(title: "MCP defaults", command: "session_show_defaults", detail: "Codex/XcodeBuildMCP session defaults show the configured project, scheme, platform, and device/simulator."),
                    .init(title: "Check Xcode", command: "xcodebuild -version", detail: "Verifies the local Xcode command-line toolchain."),
                ],
                apiKeyEnvironmentVariables: [],
                directOAuthSupported: false,
                directOAuthNote: "No browser login or OAuth callback is required. Configure the MCP connector and Xcode access in Codex.",
                docsURL: "https://xcodebuildmcp.com/docs/configuration",
                notes: [
                    "Use XcodeBuildMCP for project discovery, build/test/debug, logs, screenshots, and UI automation when those workflows are enabled.",
                    "Only simulator tools may be exposed until the user enables macOS, device, debugging, or UI automation workflows in XcodeBuildMCP.",
                ]
            )

        case "deepseek.api":
            return ProviderAuthRecipe(
                providerID: providerID,
                primaryMethod: "DeepSeek API key through compatible tools",
                billingBoundary: "DeepSeek is API-key billed unless routed through another tool's own provider/account mechanism.",
                accountLoginCommands: [
                    .init(title: "OpenCode DeepSeek", command: "opencode", detail: "Inside OpenCode, run /connect, choose DeepSeek, and enter the DeepSeek API key."),
                ],
                authProbeCommands: [
                    .init(title: "OpenCode auth list", command: "opencode auth list", detail: "Verify DeepSeek credentials in OpenCode."),
                ],
                apiKeyEnvironmentVariables: ["DEEPSEEK_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL"],
                directOAuthSupported: false,
                directOAuthNote: "DeepSeek documents API-key integrations for coding agents, not first-party OAuth for this app.",
                docsURL: "https://api-docs.deepseek.com/guides/coding_agents",
                notes: [
                    "DeepSeek can be used through Claude Code Anthropic-compatible env vars or through OpenCode /connect.",
                    "Bearer API keys are the official DeepSeek API auth mechanism.",
                ]
            )

        default:
            return ProviderAuthRecipe(
                providerID: providerID,
                primaryMethod: "Provider-specific CLI login or API key",
                billingBoundary: "Confirm the provider's account/subscription and API-key billing lanes before dispatch.",
                accountLoginCommands: [],
                authProbeCommands: [],
                apiKeyEnvironmentVariables: [],
                directOAuthSupported: false,
                directOAuthNote: "No official direct OAuth recipe is registered yet; use custom profile and provider docs.",
                docsURL: "",
                notes: []
            )
        }
    }
}
