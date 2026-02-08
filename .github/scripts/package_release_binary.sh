#!/usr/bin/env bash
set -euo pipefail

RELEASE_TAG="${RELEASE_TAG:-${1:-}}"
REPO_ROOT="${REPO_ROOT:-$(pwd)}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/dist}"
ASSET_NAME="${ASSET_NAME:-afm-api-macos-arm64.tar.gz}"
ALLOW_SOURCE_FALLBACK="${AFM_ALLOW_SOURCE_FALLBACK:-1}"

if [[ -z "$RELEASE_TAG" ]]; then
  echo "ERROR: RELEASE_TAG is required (e.g. v1.2.3)"
  exit 1
fi
if [[ ! "$RELEASE_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z]+)*$ ]]; then
  echo "ERROR: RELEASE_TAG must match v<major>.<minor>.<patch>[-suffix]"
  exit 1
fi

VERSION="${RELEASE_TAG#v}"

mkdir -p "$OUTPUT_DIR"
rm -rf "$OUTPUT_DIR/stage"
mkdir -p "$OUTPUT_DIR/stage"

ASSET_MODE="binary"
if swift build --package-path "$REPO_ROOT" -c release --product afm-api-server; then
  cp "$REPO_ROOT/bin/afm-api" "$OUTPUT_DIR/stage/afm-api"
  cp "$REPO_ROOT/.build/release/afm-api-server" "$OUTPUT_DIR/stage/afm-api-server"
  chmod +x "$OUTPUT_DIR/stage/afm-api" "$OUTPUT_DIR/stage/afm-api-server"
  perl -pi -e "s/__AFM_API_VERSION__/${VERSION}/g" "$OUTPUT_DIR/stage/afm-api"
else
  if [[ "$ALLOW_SOURCE_FALLBACK" != "1" ]]; then
    echo "ERROR: release binary build failed and source fallback is disabled."
    exit 1
  fi
  ASSET_MODE="source-fallback"
  mkdir -p "$OUTPUT_DIR/stage/bin"
  cp "$REPO_ROOT/bin/afm-api" "$OUTPUT_DIR/stage/bin/afm-api"
  cp "$REPO_ROOT/Package.swift" "$OUTPUT_DIR/stage/Package.swift"
  cp -R "$REPO_ROOT/Sources" "$OUTPUT_DIR/stage/Sources"
  chmod +x "$OUTPUT_DIR/stage/bin/afm-api"
  perl -pi -e "s/__AFM_API_VERSION__/${VERSION}/g" "$OUTPUT_DIR/stage/bin/afm-api"
fi

if [[ "$ASSET_MODE" == "binary" ]]; then
  tar -czf "$OUTPUT_DIR/$ASSET_NAME" -C "$OUTPUT_DIR/stage" afm-api afm-api-server
else
  tar -czf "$OUTPUT_DIR/$ASSET_NAME" -C "$OUTPUT_DIR/stage" bin Package.swift Sources
fi
shasum -a 256 "$OUTPUT_DIR/$ASSET_NAME" | awk '{print $1}' > "$OUTPUT_DIR/${ASSET_NAME}.sha256"

SHA="$(cat "$OUTPUT_DIR/${ASSET_NAME}.sha256")"

echo "Built asset: $OUTPUT_DIR/$ASSET_NAME"
echo "SHA256: $SHA"
echo "Mode: $ASSET_MODE"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "asset_path=$OUTPUT_DIR/$ASSET_NAME"
    echo "sha_path=$OUTPUT_DIR/${ASSET_NAME}.sha256"
    echo "sha256=$SHA"
    echo "asset_mode=$ASSET_MODE"
  } >> "$GITHUB_OUTPUT"
fi
