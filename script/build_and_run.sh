#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Agenic Load-Balancer"
BUNDLE_ID="com.zincoverde.Agenic-Load-Balancer"
PROJECT_NAME="Agenic Load-Balancer.xcodeproj"
SCHEME="Agenic Load-Balancer"
CONFIGURATION="${CONFIGURATION:-Debug}"
DESTINATION="${DESTINATION:-platform=macOS,arch=arm64}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/$PROJECT_NAME"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

DEFAULT_BUILD_BASE="/Volumes/USB256/Xcode_Projects_Storage/Agenic_Load-Balancer_Run"
if [[ ! -d "$(dirname "$DEFAULT_BUILD_BASE")" || ! -w "$(dirname "$DEFAULT_BUILD_BASE")" ]]; then
  DEFAULT_BUILD_BASE="${TMPDIR%/}/Agenic_Load-Balancer_Run"
fi

DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$DEFAULT_BUILD_BASE/DerivedData}"
APP_BUNDLE="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

usage() {
  echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
}

stop_running_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

build_app() {
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    build

  resolve_app_bundle
}

resolve_app_bundle() {
  local fallback_bundle="/Volumes/USB256/Xcode_Projects_Storage/Build/Products/$CONFIGURATION/$APP_NAME.app"
  local candidate

  for candidate in "$APP_BUNDLE" "$fallback_bundle"; do
    if [[ -d "$candidate" ]]; then
      APP_BUNDLE="$candidate"
      APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
      return 0
    fi
  done

  candidate="$(
    find "$DERIVED_DATA_PATH" "/Volumes/USB256/Xcode_Projects_Storage/Build/Products" \
      -maxdepth 4 \
      -name "$APP_NAME.app" \
      -type d \
      -print \
      -quit 2>/dev/null || true
  )"

  if [[ -n "$candidate" && -d "$candidate" ]]; then
    APP_BUNDLE="$candidate"
    APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    return 0
  fi

  echo "Built product was not found for $APP_NAME" >&2
  exit 1
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

stop_running_app
build_app

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\" OR process == \"$APP_NAME\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    usage
    exit 2
    ;;
esac
