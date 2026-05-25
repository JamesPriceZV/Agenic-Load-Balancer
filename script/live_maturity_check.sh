#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_RUN_ROOT="/Volumes/USB256/Xcode_Projects_Storage/Agenic_LiveMaturity_$(date +%Y%m%d_%H%M%S)"
if [[ ! -d "$(dirname "$DEFAULT_RUN_ROOT")" || ! -w "$(dirname "$DEFAULT_RUN_ROOT")" ]]; then
  DEFAULT_RUN_ROOT="${TMPDIR%/}/Agenic_LiveMaturity_$(date +%Y%m%d_%H%M%S)"
fi

RUN_ROOT="${RUN_ROOT:-$DEFAULT_RUN_ROOT}"
REPORT_PATH="$RUN_ROOT/live-maturity-report.md"
RUN_PROVIDER=0
RUN_FOUNDATION=0
RUN_RELEASE=0
RUN_CONFLICT=0
RUN_TWO_MAC_CONFLICT=0
RUN_AUTONOMY=0
RUN_VISUAL=0

usage() {
  cat <<'USAGE' >&2
usage: script/live_maturity_check.sh [options]

Runs repo-owned maturity checks for the live-release queue. With no options it
runs provider probe maintenance, Foundation Models live check, release
credential doctor, CloudKit conflict-drill manifest, and autonomy continuation
drill. Add --visual to include the heavier screenshot-diff UI matrix.

Options:
  --all                 Run the default live maturity set.
  --provider-probe      Run provider probe maintenance.
  --foundation-models   Run the live Foundation Models host check.
  --release             Run Developer ID/notary credential doctor.
  --cloudkit-conflict   Create a CloudKit conflict-drill manifest.
  --two-mac-cloudkit    Coordinate the physical two-Mac CloudKit drill.
  --autonomy            Run bounded autonomy continuation drill.
  --visual              Run screenshot-diff visual regression.
USAGE
}

if [[ $# -eq 0 ]]; then
  RUN_PROVIDER=1
  RUN_FOUNDATION=1
  RUN_RELEASE=1
  RUN_CONFLICT=1
  RUN_AUTONOMY=1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)
      RUN_PROVIDER=1
      RUN_FOUNDATION=1
      RUN_RELEASE=1
      RUN_CONFLICT=1
      RUN_TWO_MAC_CONFLICT=1
      RUN_AUTONOMY=1
      ;;
    --provider-probe) RUN_PROVIDER=1 ;;
    --foundation-models) RUN_FOUNDATION=1 ;;
    --release) RUN_RELEASE=1 ;;
    --cloudkit-conflict) RUN_CONFLICT=1 ;;
    --two-mac-cloudkit) RUN_TWO_MAC_CONFLICT=1 ;;
    --autonomy) RUN_AUTONOMY=1 ;;
    --visual) RUN_VISUAL=1 ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
  shift
done

mkdir -p "$RUN_ROOT"

run_and_record() {
  local name="$1"
  local slug="$2"
  shift 2
  local out="$RUN_ROOT/$slug.out"
  local status="succeeded"
  set +e
  "$@" > "$out" 2>&1
  local code=$?
  set -e
  if [[ "$code" -ne 0 ]]; then
    status="blocked-or-failed"
  fi
  {
    echo "## $name"
    echo
    echo "- Status: $status"
    echo "- Exit code: $code"
    echo "- Output: $out"
    echo
  } >> "$REPORT_PATH"
}

{
  echo "# Live Maturity Check"
  echo
  echo "- Repository: $ROOT_DIR"
  echo "- Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "- Run root: $RUN_ROOT"
  echo
} > "$REPORT_PATH"

if [[ "$RUN_PROVIDER" -eq 1 ]]; then
  run_and_record "Provider Probe Maintenance" provider-probe \
    env RUN_ROOT="$RUN_ROOT/provider-probe" "$ROOT_DIR/script/provider_probe_maintenance.sh"
fi
if [[ "$RUN_FOUNDATION" -eq 1 ]]; then
  run_and_record "Foundation Models Live Check" foundation-models \
    env RUN_ROOT="$RUN_ROOT/foundation-models" "$ROOT_DIR/script/foundation_models_check.sh"
fi
if [[ "$RUN_RELEASE" -eq 1 ]]; then
  run_and_record "Developer ID / Notary Credential Doctor" release-credentials \
    "$ROOT_DIR/script/release_candidate.sh" --verify-credentials
fi
if [[ "$RUN_CONFLICT" -eq 1 ]]; then
  run_and_record "CloudKit Conflict Drill Manifest" cloudkit-conflict \
    env RUN_ROOT="$RUN_ROOT/cloudkit-conflict" "$ROOT_DIR/script/cloudkit_conflict_drill.sh" --role local
fi
if [[ "$RUN_TWO_MAC_CONFLICT" -eq 1 ]]; then
  run_and_record "Two-Mac CloudKit Conflict Drill" two-mac-cloudkit \
    env RUN_ROOT="$RUN_ROOT/two-mac-cloudkit" "$ROOT_DIR/script/two_mac_cloudkit_drill.sh" --peer-host "${PEER_HOST:-Solaris971.local}"
fi
if [[ "$RUN_AUTONOMY" -eq 1 ]]; then
  run_and_record "Bounded Autonomy Continuation Drill" autonomy-continuation \
    env RUN_ROOT="$RUN_ROOT/autonomy-continuation" "$ROOT_DIR/script/autonomy_continuation_drill.sh"
fi
if [[ "$RUN_VISUAL" -eq 1 ]]; then
  run_and_record "Screenshot-Diff Visual Regression" visual-regression \
    env RUN_ROOT="$RUN_ROOT/visual-regression" "$ROOT_DIR/script/visual_regression.sh"
fi

cat "$REPORT_PATH"
echo
echo "live maturity report written to $REPORT_PATH"
