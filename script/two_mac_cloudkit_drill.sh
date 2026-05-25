#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PEER_HOST="${PEER_HOST:-Solaris971.local}"
PEER_USER="${PEER_USER:-}"
REMOTE_ROOT="${REMOTE_ROOT:-$ROOT_DIR}"
DRILL_ID="${DRILL_ID:-cloudkit-drill-$(date -u '+%Y%m%dT%H%M%SZ')}"
SSH_MODE="auto"

DEFAULT_RUN_ROOT="/Volumes/USB256/Xcode_Projects_Storage/Agenic_TwoMacCloudKit_$(date +%Y%m%d_%H%M%S)"
if [[ ! -d "$(dirname "$DEFAULT_RUN_ROOT")" || ! -w "$(dirname "$DEFAULT_RUN_ROOT")" ]]; then
  DEFAULT_RUN_ROOT="${TMPDIR%/}/Agenic_TwoMacCloudKit_$(date +%Y%m%d_%H%M%S)"
fi
RUN_ROOT="${RUN_ROOT:-$DEFAULT_RUN_ROOT}"
REMOTE_RUN_ROOT="${REMOTE_RUN_ROOT:-/Volumes/USB256/Xcode_Projects_Storage/Agenic_CloudKitPeer_$DRILL_ID}"

usage() {
  cat <<'USAGE' >&2
usage: script/two_mac_cloudkit_drill.sh [options]

Coordinates the physical two-Mac CloudKit conflict drill. If SSH/Remote Login is
available on the peer Mac, the script asks the peer to create its secondary
manifest and captures the output locally. If SSH is unavailable, it writes the
exact manual command to run on the peer and leaves the drill in manual-evidence
mode instead of pretending the physical proof exists.

Options:
  --peer-host HOST       Peer Mac Bonjour or DNS name. Defaults to Solaris971.local.
  --peer-user USER       Optional SSH username for the peer Mac.
  --remote-root PATH     Agenic checkout path on the peer. Defaults to this root path.
  --remote-run-root PATH Output root on the peer. Defaults under USB scratch.
  --drill-id ID          Shared drill ID used on both Macs.
  --manual               Do not attempt SSH; emit local and manual peer manifests.
  --require-ssh          Fail if the peer cannot be reached by SSH.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --peer-host)
      PEER_HOST="${2:-}"
      shift
      ;;
    --peer-user)
      PEER_USER="${2:-}"
      shift
      ;;
    --remote-root)
      REMOTE_ROOT="${2:-}"
      shift
      ;;
    --remote-run-root)
      REMOTE_RUN_ROOT="${2:-}"
      shift
      ;;
    --drill-id)
      DRILL_ID="${2:-}"
      shift
      ;;
    --manual)
      SSH_MODE="off"
      ;;
    --require-ssh)
      SSH_MODE="required"
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

mkdir -p "$RUN_ROOT"

peer_target="$PEER_HOST"
if [[ -n "$PEER_USER" ]]; then
  peer_target="$PEER_USER@$PEER_HOST"
fi

quote_remote() {
  printf '%q' "$1"
}

REMOTE_OUTPUT="$RUN_ROOT/peer-secondary-output.md"
REMOTE_ERROR="$RUN_ROOT/peer-secondary-error.txt"
REMOTE_STATUS="manual"
REMOTE_EXIT=0

remote_command="cd $(quote_remote "$REMOTE_ROOT") && RUN_ROOT=$(quote_remote "$REMOTE_RUN_ROOT") script/cloudkit_conflict_drill.sh --role secondary --drill-id $(quote_remote "$DRILL_ID")"

if [[ "$SSH_MODE" != "off" ]]; then
  set +e
  ssh -o BatchMode=yes -o ConnectTimeout=5 "$peer_target" "$remote_command" > "$REMOTE_OUTPUT" 2> "$REMOTE_ERROR"
  REMOTE_EXIT=$?
  set -e
  if [[ "$REMOTE_EXIT" -eq 0 ]]; then
    REMOTE_STATUS="ssh-paired"
  else
    REMOTE_STATUS="ssh-unavailable"
    rm -f "$REMOTE_OUTPUT"
    if [[ "$SSH_MODE" == "required" ]]; then
      cat "$REMOTE_ERROR" >&2
      exit "$REMOTE_EXIT"
    fi
  fi
fi

LOCAL_ROOT="$RUN_ROOT/local-primary"
if [[ -f "$REMOTE_OUTPUT" ]]; then
  RUN_ROOT="$LOCAL_ROOT" "$ROOT_DIR/script/cloudkit_conflict_drill.sh" \
    --role primary \
    --drill-id "$DRILL_ID" \
    --peer-evidence "$REMOTE_OUTPUT" \
    > "$RUN_ROOT/local-primary-output.md"
else
  RUN_ROOT="$LOCAL_ROOT" "$ROOT_DIR/script/cloudkit_conflict_drill.sh" \
    --role primary \
    --drill-id "$DRILL_ID" \
    > "$RUN_ROOT/local-primary-output.md"
fi

REPORT_PATH="$RUN_ROOT/two-mac-cloudkit-drill.md"
MANUAL_COMMAND="cd $(quote_remote "$REMOTE_ROOT") && RUN_ROOT=$(quote_remote "$REMOTE_RUN_ROOT") script/cloudkit_conflict_drill.sh --role secondary --drill-id $(quote_remote "$DRILL_ID")"

{
  echo "# Two-Mac CloudKit Drill"
  echo
  echo "- Repository: $ROOT_DIR"
  echo "- Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "- Drill ID: $DRILL_ID"
  echo "- Local machine: $(scutil --get ComputerName 2>/dev/null || hostname)"
  echo "- Peer target: $peer_target"
  echo "- Remote status: $REMOTE_STATUS"
  echo "- Remote exit: $REMOTE_EXIT"
  echo "- Local manifest output: $RUN_ROOT/local-primary-output.md"
  echo "- Peer output: $([[ -f "$REMOTE_OUTPUT" ]] && echo "$REMOTE_OUTPUT" || echo "not captured")"
  echo "- Peer error: $([[ -s "$REMOTE_ERROR" ]] && echo "$REMOTE_ERROR" || echo "none")"
  echo
  echo "## Peer Command"
  echo
  echo '```sh'
  echo "$MANUAL_COMMAND"
  echo '```'
  echo
  echo "## Completion Gate"
  echo
  if [[ "$REMOTE_STATUS" == "ssh-paired" ]]; then
    echo "SSH captured the peer manifest. Continue with the in-app conflict actions on both machines, then attach screenshots and CloudKit status evidence."
  else
    echo "Remote Login/SSH did not capture peer evidence. Run the peer command on Solaris971, bring the generated manifest back to this run root, then rerun with --peer-host or pass the peer report to script/cloudkit_conflict_drill.sh --peer-evidence."
  fi
  echo
  echo "Do not mark the physical CloudKit conflict drill complete until both Macs show the same container, both manifests use this drill ID, and both Conflict Center screenshots are attached."
} > "$REPORT_PATH"

cat "$REPORT_PATH"
echo
echo "two-Mac CloudKit drill report written to $REPORT_PATH"
