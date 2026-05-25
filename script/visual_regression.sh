#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_NAME="Agenic Load-Balancer.xcodeproj"
SCHEME="Agenic Load-Balancer"
DESTINATION="${DESTINATION:-platform=macOS,arch=arm64}"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

DEFAULT_RUN_ROOT="/Volumes/USB256/Xcode_Projects_Storage/Agenic_VisualRegression_$(date +%Y%m%d_%H%M%S)"
if [[ ! -d "$(dirname "$DEFAULT_RUN_ROOT")" || ! -w "$(dirname "$DEFAULT_RUN_ROOT")" ]]; then
  DEFAULT_RUN_ROOT="${TMPDIR%/}/Agenic_VisualRegression_$(date +%Y%m%d_%H%M%S)"
fi

RUN_ROOT="${RUN_ROOT:-$DEFAULT_RUN_ROOT}"
VISUAL_DIR="${ALB_VISUAL_SNAPSHOT_DIR:-$RUN_ROOT/VisualSnapshots}"
RESULT_BUNDLE="$RUN_ROOT/Results/VisualRegression.xcresult"
FALLBACK_VISUAL_DIR="/Volumes/USB256/Xcode_Projects_Storage/Agenic_VisualRegression_Latest/VisualSnapshots"

usage() {
  cat <<'USAGE' >&2
usage: script/visual_regression.sh

Runs the Sprint L visual-regression UI snapshot matrix and writes kept
screenshot attachments plus JSON fingerprint attachments into the xcresult.
Standalone PNG/JSON files under RUN_ROOT are best effort because macOS UI-test
sandboxes can deny arbitrary output-directory writes.

Environment:
  RUN_ROOT                    Output root. Defaults under /Volumes/USB256/Xcode_Projects_Storage.
  ALB_VISUAL_SNAPSHOT_DIR     Optional artifact directory. Defaults to RUN_ROOT/VisualSnapshots.
  DESTINATION                 xcodebuild destination. Defaults to platform=macOS,arch=arm64.
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

mkdir -p "$RUN_ROOT/Results" "$VISUAL_DIR"
rm -rf "$FALLBACK_VISUAL_DIR"

echo "Visual regression run root: $RUN_ROOT"
echo "Visual artifacts: $VISUAL_DIR (best-effort; xcresult attachments are authoritative)"

ALB_VISUAL_SNAPSHOT_DIR="$VISUAL_DIR" \
xcodebuild test \
  -project "$ROOT_DIR/$PROJECT_NAME" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -derivedDataPath "$RUN_ROOT/DerivedData" \
  -resultBundlePath "$RESULT_BUNDLE" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  -skipMacroValidation \
  OBJROOT="$RUN_ROOT/Build/Intermediates.noindex" \
  SYMROOT="$RUN_ROOT/Build/Products" \
  SHARED_PRECOMPS_DIR="$RUN_ROOT/Build/PrecompiledHeaders" \
  -only-testing:"Agenic Load-BalancerUITests/Agenic_Load_BalancerUITests/testSprintLVisualRegressionSnapshotMatrix"

if [[ ! -n "$(find "$VISUAL_DIR" -maxdepth 1 -type f -print -quit 2>/dev/null)" && -d "$FALLBACK_VISUAL_DIR" ]]; then
  cp -R "$FALLBACK_VISUAL_DIR/." "$VISUAL_DIR/"
fi

echo "Visual regression result bundle: $RESULT_BUNDLE"
