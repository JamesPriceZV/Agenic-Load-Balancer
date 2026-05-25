#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Agenic Load-Balancer"
BUNDLE_ID="com.zincoverde.Agenic-Load-Balancer"
PROJECT_NAME="Agenic Load-Balancer.xcodeproj"
SCHEME="Agenic Load-Balancer"
CONFIGURATION="${CONFIGURATION:-Release}"
DESTINATION="${DESTINATION:-platform=macOS,arch=arm64}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/$PROJECT_NAME"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

DEFAULT_RUN_ROOT="/Volumes/USB256/Xcode_Projects_Storage/Agenic_ReleaseCandidate_$(date +%Y%m%d_%H%M%S)"
if [[ ! -d "$(dirname "$DEFAULT_RUN_ROOT")" || ! -w "$(dirname "$DEFAULT_RUN_ROOT")" ]]; then
  DEFAULT_RUN_ROOT="${TMPDIR%/}/Agenic_ReleaseCandidate_$(date +%Y%m%d_%H%M%S)"
fi
RUN_ROOT="${RUN_ROOT:-$DEFAULT_RUN_ROOT}"

ARCHIVE_PATH="$RUN_ROOT/Archives/$APP_NAME.xcarchive"
EXPORT_PATH="$RUN_ROOT/Export"
PACKAGE_PATH="$RUN_ROOT/Packages/$APP_NAME.zip"
NOTARY_LOG_PATH="$RUN_ROOT/notary-submit.json"
DEVELOPER_ID_IDENTITY="${DEVELOPER_ID_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-${ALB_NOTARY_PROFILE:-}}"
TEAM_ID="${TEAM_ID:-}"
ALLOW_XCODE_MANAGED_SIGNING="${ALLOW_XCODE_MANAGED_SIGNING:-0}"
ALLOW_PROVISIONING_UPDATES="${ALLOW_PROVISIONING_UPDATES:-0}"

ARCHIVE_ENABLED=0
EXPORT_ENABLED=0
PACKAGE_ENABLED=0
NOTARIZE_ENABLED=0
STAPLE_ENABLED=0
VERIFY_ONLY=0
DRY_RUN=0

usage() {
  cat <<'USAGE' >&2
usage: script/release_candidate.sh [options]

Options:
  --verify-credentials   Check for a Developer ID Application identity and optional notary profile.
  --archive              Create a signed Developer ID archive.
  --export               Export the archive with developer-id export options.
  --package              Zip the exported or archived app with ditto.
  --notarize             Submit the package with xcrun notarytool and --wait.
  --staple               Staple and assess the notarized app.
  --all                  Run archive, export, package, notarize, and staple.
  --dry-run              Print the planned credential-sensitive commands.

Environment:
  RUN_ROOT               USB-backed output root. Defaults under /Volumes/USB256/Xcode_Projects_Storage.
  DEVELOPER_ID_IDENTITY  Full "Developer ID Application: ..." identity. Auto-detected when unique.
  NOTARY_PROFILE         notarytool keychain profile name. Required for --notarize.
  ALB_NOTARY_PROFILE     Alternate notarytool profile env var.
  TEAM_ID                Optional Apple Developer Team ID for exportOptions.plist.
  ALLOW_XCODE_MANAGED_SIGNING=1
                         Permit archive/export to attempt Xcode-managed
                         Developer ID signing when no local identity is visible.
  ALLOW_PROVISIONING_UPDATES=1
                         Adds -allowProvisioningUpdates for Xcode-managed signing.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --verify-credentials) VERIFY_ONLY=1 ;;
    --archive) ARCHIVE_ENABLED=1 ;;
    --export) EXPORT_ENABLED=1 ;;
    --package) PACKAGE_ENABLED=1 ;;
    --notarize) NOTARIZE_ENABLED=1; PACKAGE_ENABLED=1 ;;
    --staple) STAPLE_ENABLED=1 ;;
    --all)
      ARCHIVE_ENABLED=1
      EXPORT_ENABLED=1
      PACKAGE_ENABLED=1
      NOTARIZE_ENABLED=1
      STAPLE_ENABLED=1
      ;;
    --dry-run) DRY_RUN=1 ;;
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

fail() {
  echo "release candidate failed: $*" >&2
  exit 1
}

pass() {
  echo "ok: $*"
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "missing tool: $1"
}

quote_args() {
  printf '%q ' "$@"
  printf '\n'
}

detect_developer_id_identity() {
  local identities
  identities="$(security find-identity -p codesigning -v 2>/dev/null | grep 'Developer ID Application:' || true)"
  if [[ -n "$DEVELOPER_ID_IDENTITY" ]]; then
    if printf '%s\n' "$identities" | grep -F "\"$DEVELOPER_ID_IDENTITY\"" >/dev/null; then
      echo "$DEVELOPER_ID_IDENTITY"
      return 0
    fi
    return 1
  fi
  local count
  count="$(printf '%s\n' "$identities" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
  if [[ "$count" == "1" ]]; then
    printf '%s\n' "$identities" | sed -E 's/^.*"(Developer ID Application: .*)".*$/\1/'
    return 0
  fi
  return 1
}

developer_id_identity="$(detect_developer_id_identity || true)"
xcode_managed_signing_enabled=0

require_tool xcodebuild
require_tool codesign
require_tool security
require_tool xcrun
require_tool ditto
require_tool spctl

if [[ -z "$developer_id_identity" ]]; then
  if [[ "$ALLOW_XCODE_MANAGED_SIGNING" == "1" ]]; then
    xcode_managed_signing_enabled=1
    echo "note: no local Developer ID Application identity is visible; Xcode-managed Developer ID signing will be attempted for archive/export."
    echo "note: if this fails, install/download the Developer ID Application certificate into the login keychain or set DEVELOPER_ID_IDENTITY."
  else
    fail "no unique Developer ID Application identity found. Install a Developer ID Application certificate, set DEVELOPER_ID_IDENTITY, or set ALLOW_XCODE_MANAGED_SIGNING=1 to let xcodebuild attempt managed signing."
  fi
else
  pass "Developer ID identity available: $developer_id_identity"
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
  pass "notarytool keychain profile selected: $NOTARY_PROFILE"
else
  if [[ "$NOTARIZE_ENABLED" -eq 1 ]]; then
    fail "NOTARY_PROFILE or ALB_NOTARY_PROFILE is required for --notarize"
  fi
  echo "note: no notary profile selected; notarization step is disabled unless NOTARY_PROFILE is set."
fi

if [[ "$VERIFY_ONLY" -eq 1 && "$ARCHIVE_ENABLED" -eq 0 && "$EXPORT_ENABLED" -eq 0 && "$PACKAGE_ENABLED" -eq 0 && "$NOTARIZE_ENABLED" -eq 0 && "$STAPLE_ENABLED" -eq 0 ]]; then
  exit 0
fi

mkdir -p "$RUN_ROOT" "$EXPORT_PATH" "$(dirname "$PACKAGE_PATH")" "$(dirname "$ARCHIVE_PATH")"

run_or_print() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "+ $(quote_args "$@")"
  else
    "$@"
  fi
}

archive_app() {
  local args=(xcodebuild)
  if [[ "$ALLOW_PROVISIONING_UPDATES" == "1" ]]; then
    args+=(-allowProvisioningUpdates)
  fi
  args+=(
    archive
    -project "$PROJECT_PATH"
    -scheme "$SCHEME"
    -configuration "$CONFIGURATION"
    -destination "$DESTINATION"
    -archivePath "$ARCHIVE_PATH"
    OTHER_CODE_SIGN_FLAGS=--timestamp
  )
  if [[ "$xcode_managed_signing_enabled" -eq 1 ]]; then
    args+=(
      CODE_SIGN_STYLE=Automatic
    )
    if [[ -n "$TEAM_ID" ]]; then
      args+=(DEVELOPMENT_TEAM="$TEAM_ID")
    fi
  else
    args+=(
      CODE_SIGN_STYLE=Manual
      CODE_SIGN_IDENTITY="$developer_id_identity"
    )
  fi
  run_or_print "${args[@]}"
  pass "archive completed at $ARCHIVE_PATH"
}

write_export_options() {
  local plist="$RUN_ROOT/exportOptions.plist"
  local signing_style="manual"
  if [[ "$xcode_managed_signing_enabled" -eq 1 ]]; then
    signing_style="automatic"
  fi
  cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>signingStyle</key>
  <string>$signing_style</string>
  <key>signingCertificate</key>
  <string>Developer ID Application</string>
  <key>stripSwiftSymbols</key>
  <true/>
EOF
  if [[ -n "$TEAM_ID" ]]; then
    cat >> "$plist" <<EOF
  <key>teamID</key>
  <string>$TEAM_ID</string>
EOF
  fi
  cat >> "$plist" <<'EOF'
</dict>
</plist>
EOF
  echo "$plist"
}

export_archive() {
  local export_options
  export_options="$(write_export_options)"
  local args=(xcodebuild)
  if [[ "$ALLOW_PROVISIONING_UPDATES" == "1" ]]; then
    args+=(-allowProvisioningUpdates)
  fi
  args+=(
    -exportArchive
    -archivePath "$ARCHIVE_PATH"
    -exportPath "$EXPORT_PATH"
    -exportOptionsPlist "$export_options"
  )
  run_or_print "${args[@]}"
  pass "export completed at $EXPORT_PATH"
}

resolved_app_bundle() {
  local exported="$EXPORT_PATH/$APP_NAME.app"
  local archived="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
  if [[ -d "$exported" ]]; then
    echo "$exported"
  elif [[ -d "$archived" ]]; then
    echo "$archived"
  else
    fail "could not locate app bundle in export or archive output"
  fi
}

package_app() {
  local app_bundle
  app_bundle="$(resolved_app_bundle)"
  rm -f "$PACKAGE_PATH"
  run_or_print ditto -c -k --keepParent "$app_bundle" "$PACKAGE_PATH"
  pass "package created at $PACKAGE_PATH"
}

notarize_package() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    run_or_print xcrun notarytool submit "$PACKAGE_PATH" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json
  else
    xcrun notarytool submit "$PACKAGE_PATH" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$NOTARY_LOG_PATH"
    grep -Eq '"status"[[:space:]]*:[[:space:]]*"Accepted"' "$NOTARY_LOG_PATH" \
      || fail "notarytool did not report Accepted. See $NOTARY_LOG_PATH"
  fi
  pass "notarization accepted"
}

staple_and_assess() {
  local app_bundle
  app_bundle="$(resolved_app_bundle)"
  run_or_print xcrun stapler staple "$app_bundle"
  run_or_print spctl -a -vv --type execute "$app_bundle"
  pass "staple and Gatekeeper assessment completed"
}

if [[ "$ARCHIVE_ENABLED" -eq 1 ]]; then archive_app; fi
if [[ "$EXPORT_ENABLED" -eq 1 ]]; then export_archive; fi
if [[ "$PACKAGE_ENABLED" -eq 1 ]]; then package_app; fi
if [[ "$NOTARIZE_ENABLED" -eq 1 ]]; then notarize_package; fi
if [[ "$STAPLE_ENABLED" -eq 1 ]]; then staple_and_assess; fi

echo "release candidate drill complete"
