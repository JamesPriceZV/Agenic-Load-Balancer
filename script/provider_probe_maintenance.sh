#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_RUN_ROOT="/Volumes/USB256/Xcode_Projects_Storage/Agenic_ProviderMaintenance_$(date +%Y%m%d_%H%M%S)"
if [[ ! -d "$(dirname "$DEFAULT_RUN_ROOT")" || ! -w "$(dirname "$DEFAULT_RUN_ROOT")" ]]; then
  DEFAULT_RUN_ROOT="${TMPDIR%/}/Agenic_ProviderMaintenance_$(date +%Y%m%d_%H%M%S)"
fi

RUN_ROOT="${RUN_ROOT:-$DEFAULT_RUN_ROOT}"
BASELINE_REPORT="${BASELINE_REPORT:-}"
REPORT_PATH="$RUN_ROOT/provider-probe-maintenance.md"
CURRENT_ROOT="$RUN_ROOT/current"
DIFF_PATH="$RUN_ROOT/provider-probe-diff.patch"

usage() {
  cat <<'USAGE' >&2
usage: script/provider_probe_maintenance.sh

Runs the safe provider probe report and optionally compares it with a prior
report to surface CLI auth, quota, version, and custom-profile drift.

Environment:
  RUN_ROOT              Output directory. Defaults under /Volumes/USB256/Xcode_Projects_Storage.
  BASELINE_REPORT       Optional previous provider-probe-report.md to diff against.
  PROBE_TIMEOUT_SECONDS Per-command timeout passed to provider_probe_report.sh.
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

mkdir -p "$RUN_ROOT"

RUN_ROOT="$CURRENT_ROOT" "$ROOT_DIR/script/provider_probe_report.sh" > "$RUN_ROOT/provider-probe-report.stdout"
CURRENT_REPORT="$CURRENT_ROOT/provider-probe-report.md"

status="captured"
diff_summary="No baseline report supplied; current safe probe report captured for review."
if [[ -n "$BASELINE_REPORT" ]]; then
  if [[ ! -f "$BASELINE_REPORT" ]]; then
    status="blocked"
    diff_summary="Baseline report does not exist: $BASELINE_REPORT"
  elif diff -u "$BASELINE_REPORT" "$CURRENT_REPORT" > "$DIFF_PATH"; then
    status="stable"
    diff_summary="No provider probe drift detected against baseline."
  else
    status="changed"
    diff_summary="Provider probe drift detected. See $DIFF_PATH."
  fi
fi

{
  echo "# Provider Probe Maintenance"
  echo
  echo "- Repository: $ROOT_DIR"
  echo "- Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "- Status: $status"
  echo "- Current report: $CURRENT_REPORT"
  echo "- Baseline report: ${BASELINE_REPORT:-none}"
  echo "- Diff: $diff_summary"
  echo
  echo "## Notes"
  echo
  echo "- The probe report does not launch installers, login flows, browser auth, or device-code auth."
  echo "- Environment values are not printed; only variable names visible to this process are listed."
  echo "- Treat changed auth/quota/subscription/context text as maintenance input, not automatic failure."
} > "$REPORT_PATH"

cat "$REPORT_PATH"
echo
echo "provider probe maintenance report written to $REPORT_PATH"
