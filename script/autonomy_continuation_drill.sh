#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_RUN_ROOT="/Volumes/USB256/Xcode_Projects_Storage/Agenic_AutonomyContinuation_$(date +%Y%m%d_%H%M%S)"
if [[ ! -d "$(dirname "$DEFAULT_RUN_ROOT")" || ! -w "$(dirname "$DEFAULT_RUN_ROOT")" ]]; then
  DEFAULT_RUN_ROOT="${TMPDIR%/}/Agenic_AutonomyContinuation_$(date +%Y%m%d_%H%M%S)"
fi

RUN_ROOT="${RUN_ROOT:-$DEFAULT_RUN_ROOT}"
REPORT_PATH="$RUN_ROOT/autonomy-continuation-drill.md"
STRICT="${STRICT:-0}"

usage() {
  cat <<'USAGE' >&2
usage: script/autonomy_continuation_drill.sh

Checks that autonomous continuation remains bounded by trust lanes,
approval-gated run preparation, validation gates, and rollback evidence.

Environment:
  RUN_ROOT   Output directory. Defaults under /Volumes/USB256/Xcode_Projects_Storage.
  STRICT     When 1, exit nonzero if required safety seams are missing.
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

mkdir -p "$RUN_ROOT"

policy_file="$ROOT_DIR/Agenic Load-Balancer/Services/AutonomyPolicy.swift"
manager_file="$ROOT_DIR/Agenic Load-Balancer/Services/AutonomousProjectManager.swift"
view_file="$ROOT_DIR/Agenic Load-Balancer/Views/AutonomyControlCenterView.swift"

missing=()
grep -q "AutonomyTrustLane" "$policy_file" || missing+=("trust lanes")
grep -q "requiresApproval" "$manager_file" "$policy_file" || missing+=("approval-required decisions")
grep -q "prepareRun" "$view_file" || missing+=("approval sheet preparation")
grep -q "runValidationGate" "$view_file" || missing+=("explicit validation gate action")
grep -q "rollback" "$policy_file" "$view_file" || missing+=("rollback evidence")
grep -q "maxFilesChangedPerTask" "$policy_file" || missing+=("changed-file cap")

status="bounded"
if [[ "${#missing[@]}" -gt 0 ]]; then
  status="failed"
fi

{
  echo "# Autonomy Continuation Drill"
  echo
  echo "- Repository: $ROOT_DIR"
  echo "- Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "- Status: $status"
  echo
  echo "## Safety Seams"
  echo
  echo "- Trust lanes: $(grep -q "AutonomyTrustLane" "$policy_file" && echo present || echo missing)"
  echo "- Approval-required decisions: $(grep -q "requiresApproval" "$manager_file" "$policy_file" && echo present || echo missing)"
  echo "- Approval sheet preparation: $(grep -q "prepareRun" "$view_file" && echo present || echo missing)"
  echo "- Explicit validation action: $(grep -q "runValidationGate" "$view_file" && echo present || echo missing)"
  echo "- Rollback evidence: $(grep -q "rollback" "$policy_file" "$view_file" && echo present || echo missing)"
  echo "- Changed-file cap: $(grep -q "maxFilesChangedPerTask" "$policy_file" && echo present || echo missing)"
  echo
  if [[ "${#missing[@]}" -eq 0 ]]; then
    echo "Autonomous continuation is intentionally bounded and approval-gated. This is the safe production posture until physical recovery drills, richer summarization, and per-provider resume policies are proven."
  else
    echo "Missing safety seams: ${missing[*]}"
  fi
} > "$REPORT_PATH"

cat "$REPORT_PATH"
echo
echo "autonomy continuation drill written to $REPORT_PATH"

if [[ "$STRICT" == "1" && "$status" != "bounded" ]]; then
  exit 1
fi
