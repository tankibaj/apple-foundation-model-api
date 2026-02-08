#!/usr/bin/env bash
set -euo pipefail
export HOMEBREW_NO_GITHUB_API=1

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "FAIL: missing required command: $1"
    exit 1
  }
}

require brew
require git
require shasum
require curl
require swift

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FORMULA_NAME="${FORMULA_NAME:-afm-api}"
TAP_NAME="${1:-tankibaj/localtap}"
KEEP_INSTALL="${KEEP_INSTALL:-0}"
KEEP_TAP="${KEEP_TAP:-0}"

TAP_USER="${TAP_NAME%%/*}"
TAP_REPO="${TAP_NAME##*/}"
TAP_ROOT="$(brew --repository)/Library/Taps/${TAP_USER}/homebrew-${TAP_REPO}"
FORMULA_PATH="$TAP_ROOT/Formula/${FORMULA_NAME}.rb"

SHORT_SHA="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
VERSION="0.0.0-feature.${SHORT_SHA}"
STAGE_DIR="${TMPDIR:-/tmp}/afm-api-feature-stage-${SHORT_SHA}"
TARBALL="${TMPDIR:-/tmp}/afm-api-feature-${SHORT_SHA}.tar.gz"
BACKUP_FORMULA=""
CREATED_TAP=0

cleanup() {
  if [[ "$KEEP_INSTALL" != "1" ]]; then
    brew uninstall "${TAP_NAME}/${FORMULA_NAME}" >/dev/null 2>&1 || true
  fi

  if [[ -n "$BACKUP_FORMULA" && -f "$BACKUP_FORMULA" ]]; then
    mv "$BACKUP_FORMULA" "$FORMULA_PATH"
  elif [[ -f "$FORMULA_PATH" ]]; then
    rm -f "$FORMULA_PATH"
  fi

  if [[ "$CREATED_TAP" == "1" && "$KEEP_TAP" != "1" ]]; then
    brew untap "$TAP_NAME" >/dev/null 2>&1 || true
  fi

  rm -rf "$STAGE_DIR"
  rm -f "$TARBALL"
}
trap cleanup EXIT

if ! brew tap | rg -q "^${TAP_NAME}$"; then
  brew tap-new "$TAP_NAME" >/dev/null
  CREATED_TAP=1
fi

mkdir -p "$(dirname "$FORMULA_PATH")"
if [[ -f "$FORMULA_PATH" ]]; then
  BACKUP_FORMULA="${FORMULA_PATH}.bak.$RANDOM"
  cp "$FORMULA_PATH" "$BACKUP_FORMULA"
fi

AFM_API_SOURCE_ROOT="$REPO_ROOT" "$REPO_ROOT/bin/afm-api" build >/dev/null

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp "$REPO_ROOT/bin/afm-api" "$STAGE_DIR/afm-api"
cp "$REPO_ROOT/.build/release/afm-api-server" "$STAGE_DIR/afm-api-server"
chmod +x "$STAGE_DIR/afm-api" "$STAGE_DIR/afm-api-server"
sed -i '' "s/__AFM_API_VERSION__/${VERSION}/g" "$STAGE_DIR/afm-api"

tar -czf "$TARBALL" -C "$STAGE_DIR" afm-api afm-api-server
SHA="$(shasum -a 256 "$TARBALL" | awk '{print $1}')"

cat > "$FORMULA_PATH" <<EOF
class AfmApi < Formula
  desc "OpenAI-compatible local server for Apple Foundation Model"
  homepage "https://github.com/tankibaj/apple-foundation-model-api"
  url "file://${TARBALL}"
  version "${VERSION}"
  sha256 "${SHA}"
  license "MIT"

  depends_on :macos

  def install
    bin.install "afm-api"
    bin.install "afm-api-server"
  end

  test do
    assert_predicate bin/"afm-api", :exist?
    assert_predicate bin/"afm-api-server", :exist?
  end
end
EOF

brew reinstall "${TAP_NAME}/${FORMULA_NAME}" >/dev/null 2>&1 || true
brew list --versions "${FORMULA_NAME}" >/dev/null 2>&1 || {
  echo "FAIL: Homebrew formula install did not succeed for ${TAP_NAME}/${FORMULA_NAME}"
  exit 1
}

afm-api --stop >/dev/null 2>&1 || true
afm-api --background >/dev/null
sleep 1
curl -sf "http://127.0.0.1:8000/v1/health" >/dev/null
afm-api --stop >/dev/null 2>&1 || true

echo "PASS: Homebrew feature-branch install test works"
echo "PASS info: tap=${TAP_NAME} version=${VERSION} sha=${SHA}"
