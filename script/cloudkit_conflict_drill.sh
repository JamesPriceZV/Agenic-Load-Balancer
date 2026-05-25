#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROLE="local"
DRILL_ID="cloudkit-drill-$(date -u '+%Y%m%dT%H%M%SZ')"
PEER_EVIDENCE=""

DEFAULT_RUN_ROOT="/Volumes/USB256/Xcode_Projects_Storage/Agenic_CloudKitConflict_$(date +%Y%m%d_%H%M%S)"
if [[ ! -d "$(dirname "$DEFAULT_RUN_ROOT")" || ! -w "$(dirname "$DEFAULT_RUN_ROOT")" ]]; then
  DEFAULT_RUN_ROOT="${TMPDIR%/}/Agenic_CloudKitConflict_$(date +%Y%m%d_%H%M%S)"
fi
RUN_ROOT="${RUN_ROOT:-$DEFAULT_RUN_ROOT}"

usage() {
  cat <<'USAGE' >&2
usage: script/cloudkit_conflict_drill.sh [--role local|primary|secondary] [--drill-id ID] [--peer-evidence PATH]

Creates a role-specific physical CloudKit conflict-drill manifest. The local
app already has a synthetic Conflict Center drill; this script records the
real two-machine prerequisites and evidence needed before claiming production
multi-machine recovery.

Options:
  --role ROLE            local, primary, or secondary. Defaults to local.
  --drill-id ID          Shared drill identifier to use on both Macs.
  --peer-evidence PATH   Opposite machine manifest/report to mark the drill as paired.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role)
      ROLE="${2:-}"
      shift
      ;;
    --drill-id)
      DRILL_ID="${2:-}"
      shift
      ;;
    --peer-evidence)
      PEER_EVIDENCE="${2:-}"
      shift
      ;;
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

case "$ROLE" in
  local|primary|secondary) ;;
  *) echo "invalid role: $ROLE" >&2; exit 2 ;;
esac

mkdir -p "$RUN_ROOT"
REPORT_PATH="$RUN_ROOT/cloudkit-conflict-drill-$ROLE.md"
ENTITLEMENTS_PATH="$ROOT_DIR/Agenic Load-Balancer/Agenic_Load_Balancer.entitlements"
CONTAINER_ID="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.icloud-container-identifiers:0' "$ENTITLEMENTS_PATH" 2>/dev/null || echo unknown)"
GIT_HEAD="$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
COMPUTER_NAME="$(scutil --get ComputerName 2>/dev/null || hostname)"

status="blocked"
if [[ "$ROLE" == "local" ]]; then
  status="local-ready"
elif [[ -n "$PEER_EVIDENCE" && -f "$PEER_EVIDENCE" ]]; then
  status="paired-ready"
fi

{
  echo "# CloudKit Conflict Drill"
  echo
  echo "- Repository: $ROOT_DIR"
  echo "- Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "- Status: $status"
  echo "- Role: $ROLE"
  echo "- Drill ID: $DRILL_ID"
  echo "- Machine: $COMPUTER_NAME"
  echo "- Git HEAD: $GIT_HEAD"
  echo "- CloudKit container: $CONTAINER_ID"
  echo "- Peer evidence: ${PEER_EVIDENCE:-none}"
  echo
  echo "## Required Physical Drill"
  echo
  echo "1. Run this script on two physical Macs signed into the same iCloud account, using the same drill ID and complementary roles."
  echo "2. Launch the app from the active iCloud checkout on both machines."
  echo "3. Confirm Settings > Storage shows the expected CloudKit container and a current local/cloud event."
  echo "4. On the primary machine, open Conflicts and run the in-app recovery drill."
  echo "5. On both machines, create a small workspace/task metadata change for the same configured project."
  echo "6. Wait for CloudKit propagation, refresh iCloud status, and capture both machines' Conflict Center state."
  echo "7. Resolve with merge when audit history is commutative and restore-into-new-copy when task payloads diverge."
  echo "8. Attach both role manifests, screenshots, and any generated app reports before marking the physical drill complete."
  echo
  echo "## Local Rehearsal Gate"
  echo
  echo "The repo-local rehearsal remains the focused ConflictResolutionEngineTests plus the in-app Conflict Center Run Drill action. Passing that rehearsal is necessary but not sufficient for the physical CloudKit claim."
} > "$REPORT_PATH"

cat "$REPORT_PATH"
echo
echo "cloudkit conflict drill manifest written to $REPORT_PATH"
