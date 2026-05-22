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
ENTITLEMENTS_PATH="$ROOT_DIR/Agenic Load-Balancer/Agenic_Load_Balancer.entitlements"
PLAN_PATH="$ROOT_DIR/ReleaseReadiness.md"
Pbxproj_PATH="$PROJECT_PATH/project.pbxproj"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

DEFAULT_RUN_ROOT="/Volumes/USB256/Xcode_Projects_Storage/Agenic_Release_$(date +%Y%m%d_%H%M%S)"
if [[ ! -d "$(dirname "$DEFAULT_RUN_ROOT")" || ! -w "$(dirname "$DEFAULT_RUN_ROOT")" ]]; then
  DEFAULT_RUN_ROOT="${TMPDIR%/}/Agenic_Release_$(date +%Y%m%d_%H%M%S)"
fi
RUN_ROOT="${RUN_ROOT:-$DEFAULT_RUN_ROOT}"

BUILD_ENABLED=0
ARCHIVE_ENABLED=0
SIGNED_BUILD=0

usage() {
  cat <<'USAGE' >&2
usage: script/release_preflight.sh [--build] [--archive] [--signed-build]

Default mode checks release metadata, entitlements, docs, and tool availability.
--build        also runs a Release build into RUN_ROOT
--archive      also runs xcodebuild archive into RUN_ROOT
--signed-build do not force CODE_SIGNING_ALLOWED=NO for build/archive
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build)
      BUILD_ENABLED=1
      ;;
    --archive)
      BUILD_ENABLED=1
      ARCHIVE_ENABLED=1
      ;;
    --signed-build)
      SIGNED_BUILD=1
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

fail() {
  echo "release preflight failed: $*" >&2
  exit 1
}

pass() {
  echo "ok: $*"
}

require_file() {
  [[ -f "$1" ]] || fail "missing $1"
}

require_text() {
  local file="$1"
  local needle="$2"
  grep -Fq "$needle" "$file" || fail "missing '$needle' in $file"
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "missing tool: $1"
}

require_file "$PROJECT_PATH/project.pbxproj"
require_file "$ENTITLEMENTS_PATH"
require_file "$PLAN_PATH"
require_tool xcodebuild
require_tool plutil
require_tool codesign
require_tool xcrun

require_text "$Pbxproj_PATH" "PRODUCT_BUNDLE_IDENTIFIER = \"$BUNDLE_ID\";"
require_text "$Pbxproj_PATH" "ENABLE_HARDENED_RUNTIME = YES;"
require_text "$Pbxproj_PATH" "CODE_SIGN_ENTITLEMENTS = \"Agenic Load-Balancer/Agenic_Load_Balancer.entitlements\";"
require_text "$Pbxproj_PATH" "INFOPLIST_KEY_LSApplicationCategoryType = \"public.app-category.developer-tools\";"
require_text "$Pbxproj_PATH" "MACOSX_DEPLOYMENT_TARGET = 26.4;"
pass "project build settings declare bundle ID, hardened runtime, entitlements, category, and deployment target"

require_text "$ENTITLEMENTS_PATH" "iCloud.com.zincoverde.Agenic-Load-Balancer"
require_text "$ENTITLEMENTS_PATH" "com.apple.developer.icloud-services"
require_text "$ENTITLEMENTS_PATH" "CloudKit"
require_text "$ENTITLEMENTS_PATH" "CloudDocuments"
require_text "$ENTITLEMENTS_PATH" "com.apple.developer.ubiquity-container-identifiers"
require_text "$ENTITLEMENTS_PATH" "com.apple.developer.ubiquity-kvstore-identifier"
require_text "$ENTITLEMENTS_PATH" "com.apple.developer.aps-environment"
pass "entitlements declare CloudKit, CloudDocuments, ubiquity, key-value store, and remote notification posture"

require_text "$PLAN_PATH" "Developer ID"
require_text "$PLAN_PATH" "notarytool"
require_text "$PLAN_PATH" "stapler"
require_text "$PLAN_PATH" "Keychain"
require_text "$PLAN_PATH" "CloudKit"
pass "release readiness document covers signing, notarization, privacy, sync, and rollback"

if [[ "$BUILD_ENABLED" -eq 1 ]]; then
  mkdir -p "$RUN_ROOT"
  BUILD_ARGS=(
    -project "$PROJECT_PATH"
    -scheme "$SCHEME"
    -configuration "$CONFIGURATION"
    -destination "$DESTINATION"
    -derivedDataPath "$RUN_ROOT/DerivedData"
    SYMROOT="$RUN_ROOT/Build"
    OBJROOT="$RUN_ROOT/Intermediates"
    SHARED_PRECOMPS_DIR="$RUN_ROOT/PrecompiledHeaders"
  )
  if [[ "$SIGNED_BUILD" -eq 0 ]]; then
    BUILD_ARGS+=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=)
  fi

  xcodebuild "${BUILD_ARGS[@]}" build
  pass "Release build completed under $RUN_ROOT"

  APP_BUNDLE="$RUN_ROOT/Build/Release/$APP_NAME.app"
  if [[ -d "$APP_BUNDLE" ]]; then
    /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_BUNDLE/Contents/Info.plist" | grep -Fx "$BUNDLE_ID" >/dev/null \
      || fail "built app bundle identifier mismatch"
    pass "built app bundle identifier matches $BUNDLE_ID"
    if [[ "$SIGNED_BUILD" -eq 1 ]]; then
      codesign -dvvv --entitlements :- "$APP_BUNDLE" >/dev/null
      pass "codesign can read signed app entitlements"
    fi
  fi
fi

if [[ "$ARCHIVE_ENABLED" -eq 1 ]]; then
  ARCHIVE_PATH="$RUN_ROOT/Archives/$APP_NAME.xcarchive"
  mkdir -p "$(dirname "$ARCHIVE_PATH")"
  ARCHIVE_ARGS=(
    -project "$PROJECT_PATH"
    -scheme "$SCHEME"
    -configuration "$CONFIGURATION"
    -destination "$DESTINATION"
    -archivePath "$ARCHIVE_PATH"
  )
  if [[ "$SIGNED_BUILD" -eq 0 ]]; then
    ARCHIVE_ARGS+=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=)
  fi

  xcodebuild "${ARCHIVE_ARGS[@]}" archive
  pass "archive completed at $ARCHIVE_PATH"
fi

echo "release preflight complete"
