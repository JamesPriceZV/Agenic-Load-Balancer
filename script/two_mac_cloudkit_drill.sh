#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PEER_HOST="${PEER_HOST:-Solaris971.local}"
PEER_USER="${PEER_USER:-}"
REMOTE_ROOT="${REMOTE_ROOT:-$ROOT_DIR}"
DRILL_ID="${DRILL_ID:-cloudkit-drill-$(date -u '+%Y%m%dT%H%M%SZ')}"
SSH_MODE="auto"
PEER_BUNDLE_PATH=""
VERIFY_PEER_EVIDENCE_PATH=""
RESUME_EXISTING_RUN=0
SHOW_REMOTE_LOGIN_RUNBOOK=0

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
  --peer-host HOST            Peer Mac Bonjour or DNS name. Defaults to Solaris971.local.
  --peer-user USER            Optional SSH username for the peer Mac.
  --remote-root PATH          Agenic checkout path on the peer. Defaults to this root path.
  --remote-run-root PATH      Output root on the peer. Defaults under USB scratch.
  --drill-id ID               Shared drill ID used on both Macs.
  --manual                    Do not attempt SSH; emit local and manual peer manifests.
  --require-ssh               Fail if the peer cannot be reached by SSH.
  --resume                    Reuse a previous RUN_ROOT's primary manifest instead of re-running it.
  --peer-bundle PATH          Write a self-contained peer-run bundle (command + README + drill ID).
  --verify-peer-evidence FILE Compute sha256 of FILE, store it next to the report,
                              and reference it from the completion gate.
  --remote-login-runbook      Print Solaris971 Remote Login / sharing setup steps and exit.
USAGE
}

print_remote_login_runbook() {
  cat <<'RUNBOOK'
Sprint O.4 — Solaris971 Remote Login / SSH enablement runbook
============================================================

The two-Mac CloudKit drill talks to the peer Mac over SSH when
Remote Login is enabled. Solaris971 currently refuses port 22, so the
drill stays in manual-evidence mode. Enable Remote Login once with
the steps below, then `script/two_mac_cloudkit_drill.sh` (no flags) on
the primary will collect peer evidence automatically.

On Solaris971 (do this once per machine; admin password required)
-----------------------------------------------------------------
1. System Settings → General → Sharing → Remote Login. Toggle it on.
2. Click the (i) next to Remote Login and either:
     - "Allow access for: All users", or
     - "Allow access for: Only these users" and add your account.
3. Confirm by running on the secondary Mac:
     sudo systemsetup -getremotelogin
   The expected output is `Remote Login: On`.
4. From the primary Mac, smoke-test the connection:
     ssh -o BatchMode=yes -o ConnectTimeout=5 Solaris971.local "uname -a"
   If this fails with a permission prompt, copy your public key:
     ssh-copy-id <user>@Solaris971.local
5. The primary can now run the drill with no extra flags:
     RUN_ROOT="/Volumes/USB256/Xcode_Projects_Storage/Agenic_TwoMacCloudKit_$(date +%Y%m%d_%H%M%S)" \
       script/two_mac_cloudkit_drill.sh

If Remote Login cannot be enabled on Solaris971
-----------------------------------------------
Use the bundle path instead of SSH:

  script/two_mac_cloudkit_drill.sh --peer-bundle ~/Desktop/agenic-peer-bundle

Copy the resulting directory to Solaris971 (USB stick, AirDrop, etc.),
run `./run-peer.sh` there, then carry the generated peer manifest back to
the primary and pass it with:

  script/two_mac_cloudkit_drill.sh \
    --manual \
    --verify-peer-evidence /path/to/peer-secondary-output.md

The completion gate will only be marked satisfied when both Macs share
the same drill ID and both manifests are present.

Notes
-----
- Remote Login does not bypass FileVault prompts; on a freshly booted
  Solaris971 the user must log in once before SSH succeeds.
- This script never asks for or stores the SSH password; it only checks
  whether `BatchMode=yes` (key-based) auth works.
RUNBOOK
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
    --resume)
      RESUME_EXISTING_RUN=1
      ;;
    --peer-bundle)
      PEER_BUNDLE_PATH="${2:-}"
      shift
      ;;
    --verify-peer-evidence)
      VERIFY_PEER_EVIDENCE_PATH="${2:-}"
      shift
      ;;
    --remote-login-runbook)
      SHOW_REMOTE_LOGIN_RUNBOOK=1
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

if [[ "$SHOW_REMOTE_LOGIN_RUNBOOK" -eq 1 ]]; then
  print_remote_login_runbook
  exit 0
fi

mkdir -p "$RUN_ROOT"

peer_target="$PEER_HOST"
if [[ -n "$PEER_USER" ]]; then
  peer_target="$PEER_USER@$PEER_HOST"
fi

quote_remote() {
  printf '%q' "$1"
}

remote_command="cd $(quote_remote "$REMOTE_ROOT") && RUN_ROOT=$(quote_remote "$REMOTE_RUN_ROOT") script/cloudkit_conflict_drill.sh --role secondary --drill-id $(quote_remote "$DRILL_ID")"

# Sprint O.4: peer-bundle path. Writes a self-contained directory the user
# can ferry to Solaris971 manually (USB stick, AirDrop, etc.) when SSH is
# refused. The bundle never contains secrets — only the drill ID, the
# expected output path, and a wrapper that invokes the existing
# cloudkit_conflict_drill.sh on the peer side.
if [[ -n "$PEER_BUNDLE_PATH" ]]; then
  mkdir -p "$PEER_BUNDLE_PATH"
  cat > "$PEER_BUNDLE_PATH/drill-id.txt" <<EOF
$DRILL_ID
EOF
  cat > "$PEER_BUNDLE_PATH/README.md" <<EOF
# Agenic two-Mac CloudKit peer bundle

This bundle was generated on the primary Mac at $(date -u '+%Y-%m-%dT%H:%M:%SZ').
Carry it to the peer Mac ($peer_target) and run \`./run-peer.sh\` from
this directory. It assumes the Agenic Load-Balancer checkout is at:

    $REMOTE_ROOT

If the peer checkout lives elsewhere, set REMOTE_ROOT before invoking the
wrapper, e.g.:

    REMOTE_ROOT=/path/to/checkout ./run-peer.sh

The wrapper writes a peer manifest under:

    $REMOTE_RUN_ROOT

Bring that manifest back to the primary Mac and rerun:

    script/two_mac_cloudkit_drill.sh \\
      --manual \\
      --verify-peer-evidence /path/to/peer-secondary-output.md

The drill ID in this bundle is:

    $DRILL_ID

Do not edit drill-id.txt; both Macs must agree on the same drill ID.
EOF
  cat > "$PEER_BUNDLE_PATH/run-peer.sh" <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail
BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRILL_ID="$(tr -d '[:space:]' < "$BUNDLE_DIR/drill-id.txt")"
REMOTE_ROOT="${REMOTE_ROOT:-}"
REMOTE_RUN_ROOT="${REMOTE_RUN_ROOT:-}"
if [[ -z "$REMOTE_ROOT" ]]; then
  echo "REMOTE_ROOT is not set. Point it at the Agenic Load-Balancer checkout on this Mac." >&2
  exit 2
fi
if [[ -z "$REMOTE_RUN_ROOT" ]]; then
  REMOTE_RUN_ROOT="$BUNDLE_DIR/peer-run"
  mkdir -p "$REMOTE_RUN_ROOT"
fi
cd "$REMOTE_ROOT"
RUN_ROOT="$REMOTE_RUN_ROOT" script/cloudkit_conflict_drill.sh --role secondary --drill-id "$DRILL_ID"
echo "Peer manifest is under: $REMOTE_RUN_ROOT"
WRAPPER
  cat > "$PEER_BUNDLE_PATH/run-peer.command" <<EOF
#!/usr/bin/env bash
set -e
cd "\$(dirname "\${BASH_SOURCE[0]}")"
REMOTE_ROOT="\${REMOTE_ROOT:-$REMOTE_ROOT}" REMOTE_RUN_ROOT="\${REMOTE_RUN_ROOT:-$REMOTE_RUN_ROOT}" ./run-peer.sh
EOF
  chmod +x "$PEER_BUNDLE_PATH/run-peer.sh" "$PEER_BUNDLE_PATH/run-peer.command"
  echo "peer bundle written to $PEER_BUNDLE_PATH"
fi

REMOTE_OUTPUT="$RUN_ROOT/peer-secondary-output.md"
REMOTE_ERROR="$RUN_ROOT/peer-secondary-error.txt"
REMOTE_STATUS="manual"
REMOTE_EXIT=0

# Sprint O.4: --verify-peer-evidence — copy the manual manifest into the
# run root and record its sha256 so the completion gate can prove the
# referenced peer file is the one that was reviewed.
PEER_EVIDENCE_CHECKSUM=""
if [[ -n "$VERIFY_PEER_EVIDENCE_PATH" ]]; then
  if [[ ! -f "$VERIFY_PEER_EVIDENCE_PATH" ]]; then
    echo "verify-peer-evidence: $VERIFY_PEER_EVIDENCE_PATH is not a file" >&2
    exit 2
  fi
  cp "$VERIFY_PEER_EVIDENCE_PATH" "$REMOTE_OUTPUT"
  PEER_EVIDENCE_CHECKSUM="$(shasum -a 256 "$REMOTE_OUTPUT" | awk '{print $1}')"
  echo "$PEER_EVIDENCE_CHECKSUM  $(basename "$REMOTE_OUTPUT")" > "$RUN_ROOT/peer-secondary-output.sha256"
  REMOTE_STATUS="manual-verified"
fi

if [[ "$SSH_MODE" != "off" && -z "$PEER_EVIDENCE_CHECKSUM" ]]; then
  set +e
  ssh -o BatchMode=yes -o ConnectTimeout=5 "$peer_target" "$remote_command" > "$REMOTE_OUTPUT" 2> "$REMOTE_ERROR"
  REMOTE_EXIT=$?
  set -e
  if [[ "$REMOTE_EXIT" -eq 0 ]]; then
    REMOTE_STATUS="ssh-paired"
    PEER_EVIDENCE_CHECKSUM="$(shasum -a 256 "$REMOTE_OUTPUT" | awk '{print $1}')"
    echo "$PEER_EVIDENCE_CHECKSUM  $(basename "$REMOTE_OUTPUT")" > "$RUN_ROOT/peer-secondary-output.sha256"
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
LOCAL_PRIMARY_OUTPUT="$RUN_ROOT/local-primary-output.md"

if [[ "$RESUME_EXISTING_RUN" -eq 1 && -f "$LOCAL_PRIMARY_OUTPUT" ]]; then
  echo "resume: reusing existing local primary manifest at $LOCAL_PRIMARY_OUTPUT"
else
  if [[ -f "$REMOTE_OUTPUT" ]]; then
    RUN_ROOT="$LOCAL_ROOT" "$ROOT_DIR/script/cloudkit_conflict_drill.sh" \
      --role primary \
      --drill-id "$DRILL_ID" \
      --peer-evidence "$REMOTE_OUTPUT" \
      > "$LOCAL_PRIMARY_OUTPUT"
  else
    RUN_ROOT="$LOCAL_ROOT" "$ROOT_DIR/script/cloudkit_conflict_drill.sh" \
      --role primary \
      --drill-id "$DRILL_ID" \
      > "$LOCAL_PRIMARY_OUTPUT"
  fi
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
  echo "- Local manifest output: $LOCAL_PRIMARY_OUTPUT"
  echo "- Peer output: $([[ -f "$REMOTE_OUTPUT" ]] && echo "$REMOTE_OUTPUT" || echo "not captured")"
  echo "- Peer error: $([[ -s "$REMOTE_ERROR" ]] && echo "$REMOTE_ERROR" || echo "none")"
  if [[ -n "$PEER_EVIDENCE_CHECKSUM" ]]; then
    echo "- Peer evidence sha256: $PEER_EVIDENCE_CHECKSUM"
  fi
  if [[ -n "$PEER_BUNDLE_PATH" ]]; then
    echo "- Peer bundle: $PEER_BUNDLE_PATH"
  fi
  echo
  echo "## Peer Command"
  echo
  echo '```sh'
  echo "$MANUAL_COMMAND"
  echo '```'
  echo
  echo "## Completion Gate"
  echo
  case "$REMOTE_STATUS" in
    ssh-paired)
      echo "SSH captured the peer manifest. Continue with the in-app conflict actions on both machines, then attach screenshots and CloudKit status evidence."
      ;;
    manual-verified)
      echo "Manual peer evidence was verified. The sha256 of the peer manifest is recorded above; if it drifts later, the completion gate is no longer satisfied."
      ;;
    *)
      echo "Remote Login/SSH did not capture peer evidence. Run the peer command on Solaris971, bring the generated manifest back to this run root, then rerun with --peer-host or pass the peer report to script/cloudkit_conflict_drill.sh --peer-evidence. See script/two_mac_cloudkit_drill.sh --remote-login-runbook for the SSH enablement steps."
      ;;
  esac
  echo
  echo "Do not mark the physical CloudKit conflict drill complete until both Macs show the same container, both manifests use this drill ID, both peer outputs hash to the recorded sha256, and both Conflict Center screenshots are attached."
} > "$REPORT_PATH"

cat "$REPORT_PATH"
echo
echo "two-Mac CloudKit drill report written to $REPORT_PATH"
