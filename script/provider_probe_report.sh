#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROBE_TIMEOUT_SECONDS="${PROBE_TIMEOUT_SECONDS:-8}"

DEFAULT_RUN_ROOT="/Volumes/USB256/Xcode_Projects_Storage/Agenic_ProviderProbe_$(date +%Y%m%d_%H%M%S)"
if [[ ! -d "$(dirname "$DEFAULT_RUN_ROOT")" || ! -w "$(dirname "$DEFAULT_RUN_ROOT")" ]]; then
  DEFAULT_RUN_ROOT="${TMPDIR%/}/Agenic_ProviderProbe_$(date +%Y%m%d_%H%M%S)"
fi
RUN_ROOT="${RUN_ROOT:-$DEFAULT_RUN_ROOT}"
REPORT_PATH="$RUN_ROOT/provider-probe-report.md"
PROBE_DIR="$RUN_ROOT/probes"

mkdir -p "$PROBE_DIR"

usage() {
  cat <<'USAGE' >&2
usage: script/provider_probe_report.sh

Creates a safe provider-probe Markdown report without launching login flows,
installers, browser auth, or commands that print secret values.
Safe diagnostic auth probes include `gh auth status` and `opencode auth list`.

Environment:
  RUN_ROOT                 Output directory. Defaults under /Volumes/USB256/Xcode_Projects_Storage.
  PROBE_TIMEOUT_SECONDS    Per-command timeout. Defaults to 8 seconds.
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

escape_cell() {
  local value="${1:-}"
  value="${value//$'\n'/ }"
  value="${value//$'\r'/ }"
  value="${value//|/\\|}"
  printf '%s' "$value"
}

join_present_env() {
  local present=()
  local key
  for key in "$@"; do
    if [[ -n "${!key:-}" ]]; then
      present+=("$key")
    fi
  done
  if [[ "${#present[@]}" -eq 0 ]]; then
    printf 'none visible'
  else
    local IFS=', '
    printf '%s' "${present[*]}"
  fi
}

find_binary() {
  local candidate
  for candidate in "$@"; do
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
  done
  return 1
}

compact_file_text() {
  local file="$1"
  if [[ ! -s "$file" ]]; then
    printf 'no output'
    return 0
  fi
  tr '\n\r' '  ' < "$file" \
    | sed -E 's/[[:space:]]+/ /g; s/Token: [^ ]+/Token: [redacted]/g; s/(sk-[A-Za-z0-9_-]{8})[A-Za-z0-9_-]+/\1.../g; s/([A-Za-z0-9_]{4})[A-Za-z0-9_]{16,}/\1.../g' \
    | cut -c 1-220
}

run_probe() {
  local slug="$1"
  shift
  local out="$PROBE_DIR/$slug.out"
  local err="$PROBE_DIR/$slug.err"
  local status_file="$PROBE_DIR/$slug.status"
  rm -f "$out" "$err" "$status_file"

  (set +e; "$@" >"$out" 2>"$err"; printf '%s' "$?" > "$status_file") &
  local pid="$!"
  local elapsed=0
  while kill -0 "$pid" >/dev/null 2>&1; do
    if [[ "$elapsed" -ge "$PROBE_TIMEOUT_SECONDS" ]]; then
      kill "$pid" >/dev/null 2>&1 || true
      wait "$pid" >/dev/null 2>&1 || true
      printf 'timeout after %ss' "$PROBE_TIMEOUT_SECONDS"
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  wait "$pid" >/dev/null 2>&1 || true

  local status="unknown"
  if [[ -f "$status_file" ]]; then
    status="$(cat "$status_file")"
  fi
  local combined="$PROBE_DIR/$slug.combined"
  cat "$out" "$err" > "$combined"
  printf 'exit %s: %s' "$status" "$(compact_file_text "$combined")"
}

version_probe() {
  local slug="$1"
  local binary="$2"
  shift 2
  if [[ -z "$binary" ]]; then
    printf 'missing'
    return 0
  fi
  run_probe "$slug" "$binary" "$@"
}

auth_probe() {
  local slug="$1"
  local binary="$2"
  shift 2
  if [[ -z "$binary" ]]; then
    printf 'not run'
    return 0
  fi
  run_probe "$slug" "$binary" "$@"
}

append_row() {
  local provider="$1"
  local binary="$2"
  local install="$3"
  local auth_lane="$4"
  local version="$5"
  local auth="$6"
  local notes="$7"

  {
    printf '| %s ' "$(escape_cell "$provider")"
    printf '| %s ' "$(escape_cell "$binary")"
    printf '| %s ' "$(escape_cell "$install")"
    printf '| %s ' "$(escape_cell "$auth_lane")"
    printf '| %s ' "$(escape_cell "$version")"
    printf '| %s ' "$(escape_cell "$auth")"
    printf '| %s |\n' "$(escape_cell "$notes")"
  } >> "$REPORT_PATH"
}

{
  echo "# Provider Probe Report"
  echo
  echo "- Repository: $ROOT_DIR"
  echo "- Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "- Timeout: ${PROBE_TIMEOUT_SECONDS}s per command"
  echo "- Secret policy: environment values are not printed; only variable names present in the current process are listed."
  echo "- Login policy: this report does not run login, installer, browser, or device-code flows."
  echo
  echo "| Provider | Binary | Install | Auth lane | Version probe | Auth probe | Notes |"
  echo "| --- | --- | --- | --- | --- | --- | --- |"
} > "$REPORT_PATH"

codex_bin="$(find_binary codex || true)"
append_row \
  "Codex CLI" \
  "${codex_bin:-codex}" \
  "$([[ -n "$codex_bin" ]] && echo available || echo missing)" \
  "$(join_present_env OPENAI_API_KEY)" \
  "$(version_probe codex-version "$codex_bin" --version)" \
  "version-only; run provider-owned sign-in manually when needed" \
  "ChatGPT login and API-key billing are separate lanes."

claude_bin="$(find_binary claude || true)"
append_row \
  "Claude Code" \
  "${claude_bin:-claude}" \
  "$([[ -n "$claude_bin" ]] && echo available || echo missing)" \
  "$(join_present_env ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL)" \
  "$(version_probe claude-version "$claude_bin" --version)" \
  "$(auth_probe claude-doctor "$claude_bin" doctor)" \
  "Doctor is non-login diagnostic output; cloud-provider auth remains provider-owned."

gh_bin="$(find_binary gh || true)"
append_row \
  "GitHub Copilot CLI" \
  "${gh_bin:-gh}" \
  "$([[ -n "$gh_bin" ]] && echo available || echo missing)" \
  "$(join_present_env COPILOT_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN COPILOT_PROVIDER_API_KEY)" \
  "$(version_probe gh-version "$gh_bin" --version)" \
  "$(auth_probe gh-auth "$gh_bin" auth status)" \
  "Checks GitHub CLI fallback auth only; no device-code flow is started."

gemini_bin="$(find_binary gemini || true)"
append_row \
  "Gemini CLI" \
  "${gemini_bin:-gemini}" \
  "$([[ -n "$gemini_bin" ]] && echo available || echo missing)" \
  "$(join_present_env GEMINI_API_KEY GOOGLE_API_KEY)" \
  "$(version_probe gemini-version "$gemini_bin" --version)" \
  "version-only; run provider-owned /auth manually when needed" \
  "Google account, Gemini API key, and Vertex AI are distinct quota lanes."

cursor_bin="$(find_binary cursor-agent || true)"
append_row \
  "Cursor Agent" \
  "${cursor_bin:-cursor-agent}" \
  "$([[ -n "$cursor_bin" ]] && echo available || echo missing)" \
  "$(join_present_env CURSOR_API_KEY)" \
  "$(version_probe cursor-version "$cursor_bin" --version)" \
  "$(auth_probe cursor-status "$cursor_bin" status)" \
  "Status is a local account/endpoint probe when supported by the installed agent."

kiro_bin="$(find_binary kiro q || true)"
kiro_label="${kiro_bin:-kiro/q}"
append_row \
  "Kiro / Amazon Q" \
  "$kiro_label" \
  "$([[ -n "$kiro_bin" ]] && echo available || echo missing)" \
  "$(join_present_env AWS_PROFILE AWS_REGION)" \
  "$(version_probe kiro-version "$kiro_bin" --version)" \
  "version-only; Builder ID/IAM Identity Center login is provider-owned" \
  "Supports Kiro CLI or legacy Amazon Q CLI discovery."

qwen_bin="$(find_binary qwen || true)"
append_row \
  "Qwen Code" \
  "${qwen_bin:-qwen}" \
  "$([[ -n "$qwen_bin" ]] && echo available || echo missing)" \
  "$(join_present_env DASHSCOPE_API_KEY OPENAI_API_KEY OPENROUTER_API_KEY)" \
  "$(version_probe qwen-version "$qwen_bin" --version)" \
  "version-only; use qwen /auth manually when needed" \
  "OAuth-free tier is not treated as a live option."

vibe_bin="$(find_binary vibe || true)"
append_row \
  "Mistral Vibe" \
  "${vibe_bin:-vibe}" \
  "$([[ -n "$vibe_bin" ]] && echo available || echo missing)" \
  "$(join_present_env MISTRAL_API_KEY OPENROUTER_API_KEY)" \
  "$(version_probe vibe-version "$vibe_bin" --version)" \
  "version-only; setup is provider-owned" \
  "API-key configuration is separate from Le Chat subscription surfaces."

opencode_bin="$(find_binary opencode || true)"
append_row \
  "OpenCode" \
  "${opencode_bin:-opencode}" \
  "$([[ -n "$opencode_bin" ]] && echo available || echo missing)" \
  "$(join_present_env OPENAI_API_KEY ANTHROPIC_API_KEY DEEPSEEK_API_KEY AWS_PROFILE)" \
  "$(version_probe opencode-version "$opencode_bin" --version)" \
  "$(auth_probe opencode-auth "$opencode_bin" auth list)" \
  "OpenCode brokers auth to selected model providers."

append_row \
  "Apple Foundation Models" \
  "in-process" \
  "built-in" \
  "no auth required" \
  "app diagnostic required" \
  "app diagnostic required" \
  "Use Settings > Agents diagnostics for SystemLanguageModel.default.availability."

xcodebuild_bin="$(find_binary xcodebuild || true)"
append_row \
  "XcodeBuildMCP" \
  "${xcodebuild_bin:-xcodebuild}" \
  "$([[ -n "$xcodebuild_bin" ]] && echo available || echo missing)" \
  "no auth required" \
  "$(version_probe xcodebuild-version "$xcodebuild_bin" -version)" \
  "MCP connector is Codex-hosted; use session_show_defaults in XcodeBuildMCP" \
  "Tool source for Xcode project discovery, build/test/debug, logs, screenshots, and UI automation when configured."

append_row \
  "DeepSeek API" \
  "custom profile" \
  "custom" \
  "$(join_present_env DEEPSEEK_API_KEY OPENAI_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL)" \
  "custom profile required" \
  "custom profile required" \
  "Compatible tools should be configured without storing secrets in SwiftData or CloudKit."

cat "$REPORT_PATH"
echo
echo "provider probe report written to $REPORT_PATH"
