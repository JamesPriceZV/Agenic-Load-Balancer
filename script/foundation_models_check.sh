#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_RUN_ROOT="/Volumes/USB256/Xcode_Projects_Storage/Agenic_FoundationModels_$(date +%Y%m%d_%H%M%S)"
if [[ ! -d "$(dirname "$DEFAULT_RUN_ROOT")" || ! -w "$(dirname "$DEFAULT_RUN_ROOT")" ]]; then
  DEFAULT_RUN_ROOT="${TMPDIR%/}/Agenic_FoundationModels_$(date +%Y%m%d_%H%M%S)"
fi

RUN_ROOT="${RUN_ROOT:-$DEFAULT_RUN_ROOT}"
REPORT_PATH="$RUN_ROOT/foundation-models-check.md"
PROBE_PATH="$RUN_ROOT/FoundationModelsProbe.swift"
OUTPUT_PATH="$RUN_ROOT/foundation-models-output.txt"
STRICT="${STRICT:-0}"

usage() {
  cat <<'USAGE' >&2
usage: script/foundation_models_check.sh

Runs a live host-level Apple Foundation Models availability and minimal
LanguageModelSession response check. This does not mutate app data and does
not require provider credentials.

Environment:
  RUN_ROOT   Output directory. Defaults under /Volumes/USB256/Xcode_Projects_Storage.
  STRICT     When 1, exit nonzero if the live happy path is not available.
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

mkdir -p "$RUN_ROOT"

cat > "$PROBE_PATH" <<'SWIFT'
import Foundation

#if canImport(FoundationModels)
import FoundationModels

if #available(macOS 26.0, *) {
    print("framework=available")
    let availability = SystemLanguageModel.default.availability
    print("availability=\(availability)")
    if case .available = availability {
        let started = Date()
        let session = LanguageModelSession()
        let response = try await session.respond(to: "Reply with exactly: OK")
        print("response=\(response.content.trimmingCharacters(in: .whitespacesAndNewlines))")
        print("durationSeconds=\(Date().timeIntervalSince(started))")
    } else {
        print("response=skipped")
    }
} else {
    print("framework=available")
    print("availability=macOS < 26")
    print("response=skipped")
}
#else
print("framework=unavailable")
print("availability=FoundationModels framework unavailable")
print("response=skipped")
#endif
SWIFT

set +e
xcrun swift "$PROBE_PATH" > "$OUTPUT_PATH" 2>&1
status=$?
set -e

probe_text="$(cat "$OUTPUT_PATH")"
summary="blocked"
if [[ "$status" -ne 0 ]]; then
  summary="failed"
elif grep -q '^availability=available' "$OUTPUT_PATH" && grep -q '^response=' "$OUTPUT_PATH" && ! grep -q '^response=skipped' "$OUTPUT_PATH"; then
  summary="succeeded"
fi

{
  echo "# Foundation Models Live Check"
  echo
  echo "- Repository: $ROOT_DIR"
  echo "- Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "- Status: $summary"
  echo "- macOS: $(sw_vers -productVersion 2>/dev/null || echo unknown)"
  echo "- Xcode: $(xcodebuild -version 2>/dev/null | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g' || echo unknown)"
  echo
  echo "## Probe Output"
  echo
  echo '```text'
  printf '%s\n' "$probe_text"
  echo '```'
  echo
  if [[ "$summary" == "succeeded" ]]; then
    echo "The host reported Foundation Models availability and returned a minimal LanguageModelSession response."
  elif [[ "$summary" == "blocked" ]]; then
    echo "The live happy path is blocked on this host. Re-run on an eligible macOS 26.x machine with Apple Intelligence and the model ready."
  else
    echo "The live happy path failed unexpectedly; inspect the probe output before treating Foundation Models as ready."
  fi
} > "$REPORT_PATH"

cat "$REPORT_PATH"
echo
echo "foundation models check written to $REPORT_PATH"

if [[ "$STRICT" == "1" && "$summary" != "succeeded" ]]; then
  exit 1
fi
