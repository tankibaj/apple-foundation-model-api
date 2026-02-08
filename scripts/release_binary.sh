#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}ℹ️  $*${NC}"; }
ok() { echo -e "${GREEN}✅ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
fail() { echo -e "${RED}❌ $*${NC}" >&2; exit 1; }

usage() {
  cat <<USAGE
Usage: scripts/release_binary.sh [--version vX.Y.Z | --bump patch|minor|major] [--skip-smoke]

Creates a stable prebuilt release and verifies Homebrew install/runtime.

Options:
  --version TAG     Explicit release tag, e.g. v1.2.4
  --bump TYPE       Version bump strategy when --version is not set (default: patch)
  --skip-smoke      Skip Homebrew reinstall + runtime smoke test
  --help            Show this message
USAGE
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

version_ge() {
  local current="$1"
  local required="$2"
  [[ "$(printf '%s\n%s\n' "$required" "$current" | sort -V | tail -n1)" == "$current" ]]
}

check_macos_version() {
  [[ "$(uname -s)" == "Darwin" ]] || fail "This release script only runs on macOS."

  local required="26.0"
  local detected
  detected="$(sw_vers -productVersion 2>/dev/null || true)"
  [[ -n "$detected" ]] || fail "Unable to read macOS version via sw_vers."

  info "Detected macOS $detected"
  if version_ge "$detected" "$required"; then
    ok "macOS version check passed (required >= $required)."
  else
    fail "macOS $detected is not supported for stable release builds (required >= $required)."
  fi
}

check_swift_toolchain() {
  command -v swift >/dev/null 2>&1 || fail "Swift compiler not found. Install Xcode Command Line Tools."

  local output swift_version
  output="$(swift --version 2>&1 || true)"
  swift_version="$(printf '%s\n' "$output" | sed -nE 's/.*Apple Swift version ([0-9]+\.[0-9]+).*/\1/p' | head -n1)"

  if [[ -z "$swift_version" ]]; then
    warn "Could not parse Swift version from 'swift --version'. Continuing."
    return
  fi

  info "Detected Swift $swift_version"
  if version_ge "$swift_version" "6.0"; then
    ok "Swift toolchain check passed."
  else
    warn "Swift $swift_version is older than recommended (6.0+)."
  fi
}

check_xcode_clt() {
  command -v xcode-select >/dev/null 2>&1 || fail "xcode-select not found."
  local dev_dir
  dev_dir="$(xcode-select -p 2>/dev/null || true)"
  [[ -n "$dev_dir" ]] || fail "Xcode Command Line Tools are not configured. Run: xcode-select --install"
  ok "Xcode Command Line Tools detected at $dev_dir."
}

validate_build_prereqs() {
  check_macos_version
  check_swift_toolchain
  check_xcode_clt
}

latest_stable_tag() {
  local latest
  latest="$(git tag --list 'v*' | rg '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n1 || true)"
  if [[ -z "$latest" ]]; then
    echo "v0.0.0"
  else
    echo "$latest"
  fi
}

compute_next_tag() {
  local latest="$1"
  local bump="$2"
  local major minor patch

  IFS='.' read -r major minor patch <<< "${latest#v}"
  major=${major:-0}
  minor=${minor:-0}
  patch=${patch:-0}

  case "$bump" in
    major)
      major=$((major + 1))
      minor=0
      patch=0
      ;;
    minor)
      minor=$((minor + 1))
      patch=0
      ;;
    patch)
      patch=$((patch + 1))
      ;;
    *)
      fail "Invalid --bump value '$bump'. Expected: patch|minor|major"
      ;;
  esac

  echo "v${major}.${minor}.${patch}"
}

find_recent_update_tap_run() {
  local since_epoch="$1"
  gh run list \
    --workflow "Update Homebrew Tap" \
    --limit 30 \
    --json databaseId,createdAt,event,headBranch,status,conclusion \
    | jq -r --argjson since "$since_epoch" '
      map(select(.headBranch == "main"))
      | map(. + {ts: (.createdAt | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime)})
      | map(select(.ts >= $since))
      | sort_by(.ts)
      | reverse
      | .[0].databaseId // empty
    '
}

wait_for_tap_update_run() {
  local since_epoch="$1"
  local run_id=""

  for _ in {1..24}; do
    run_id="$(find_recent_update_tap_run "$since_epoch")"
    if [[ -n "$run_id" ]]; then
      echo "$run_id"
      return
    fi
    sleep 5
  done

  echo ""
}

smoke_test_homebrew_release() {
  local expected_version="$1"
  local runtime_dir port health
  runtime_dir="$(mktemp -d /tmp/afm-api-release-smoke.XXXXXX)"
  port=8019

  info "Running Homebrew smoke test for afm-api $expected_version"
  brew update >/dev/null
  brew reinstall tankibaj/tap/afm-api

  local installed_version
  installed_version="$(brew info tankibaj/tap/afm-api --json=v2 | jq -r '.[0].versions.stable')"
  [[ "$installed_version" == "$expected_version" ]] || fail "Installed brew version ($installed_version) does not match expected ($expected_version)."

  local cli_version
  cli_version="$(afm-api --version | awk '{print $2}')"
  [[ "$cli_version" == "$expected_version" ]] || fail "afm-api --version returned '$cli_version' (expected '$expected_version')."

  local server_bin
  server_bin="$(command -v afm-api-server || true)"
  [[ -n "$server_bin" ]] || fail "Prebuilt server binary not found on PATH after brew install (afm-api-server missing)."
  [[ -x "$server_bin" ]] || fail "afm-api-server exists but is not executable: $server_bin"
  ok "Verified prebuilt server binary: $server_bin"

  AFM_API_RUNTIME_DIR="$runtime_dir" afm-api --background --port "$port"

  set +e
  health="$(curl -fsS "http://127.0.0.1:${port}/v1/health")"
  curl_status=$?
  set -e

  if [[ $curl_status -ne 0 ]]; then
    warn "Health check failed. Log tail:"
    tail -n 120 "$runtime_dir/afm-api.log" || true
    AFM_API_RUNTIME_DIR="$runtime_dir" afm-api --stop >/dev/null 2>&1 || true
    rm -rf "$runtime_dir"
    fail "Smoke test failed: /v1/health was not reachable."
  fi

  echo "$health" | jq -e '.ok == true' >/dev/null || {
    warn "Unexpected /v1/health response: $health"
    AFM_API_RUNTIME_DIR="$runtime_dir" afm-api --stop >/dev/null 2>&1 || true
    rm -rf "$runtime_dir"
    fail "Smoke test failed: /v1/health did not return ok=true."
  }

  AFM_API_RUNTIME_DIR="$runtime_dir" afm-api --stop >/dev/null
  rm -rf "$runtime_dir"
  ok "Homebrew smoke test passed."
}

BUMP_TYPE="patch"
RELEASE_TAG=""
SKIP_SMOKE="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      RELEASE_TAG="${2:-}"
      shift
      ;;
    --bump)
      BUMP_TYPE="${2:-}"
      shift
      ;;
    --skip-smoke)
      SKIP_SMOKE="1"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
  shift
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

require_cmd git
require_cmd gh
require_cmd jq
require_cmd curl
require_cmd tar

[[ -f "Package.swift" ]] || fail "Run this script from the repository root."

git fetch origin main --tags --quiet

current_branch="$(git rev-parse --abbrev-ref HEAD)"
[[ "$current_branch" == "main" ]] || fail "Release must run from main branch. Current: $current_branch"

[[ -z "$(git status --porcelain)" ]] || fail "Working tree is not clean. Commit/stash changes first."

local_sha="$(git rev-parse HEAD)"
remote_sha="$(git rev-parse origin/main)"
[[ "$local_sha" == "$remote_sha" ]] || fail "Local main is not in sync with origin/main. Pull/push first."

if [[ -z "$RELEASE_TAG" ]]; then
  last_tag="$(latest_stable_tag)"
  RELEASE_TAG="$(compute_next_tag "$last_tag" "$BUMP_TYPE")"
fi

[[ "$RELEASE_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Stable release tag must match v<major>.<minor>.<patch>."

if git rev-parse "$RELEASE_TAG" >/dev/null 2>&1; then
  fail "Tag $RELEASE_TAG already exists. Use a new version."
fi

if gh release view "$RELEASE_TAG" >/dev/null 2>&1; then
  fail "GitHub release $RELEASE_TAG already exists. Use a new version."
fi

validate_build_prereqs

info "Creating git tag $RELEASE_TAG"
git tag -a "$RELEASE_TAG" -m "$RELEASE_TAG"
git push origin "$RELEASE_TAG"

info "Creating draft release $RELEASE_TAG"
gh release create "$RELEASE_TAG" \
  --target "$local_sha" \
  --title "$RELEASE_TAG" \
  --generate-notes \
  --draft

info "Building prebuilt release asset (source fallback disabled)"
RELEASE_TAG="$RELEASE_TAG" AFM_ALLOW_SOURCE_FALLBACK=0 ./.github/scripts/package_release_binary.sh

ASSET_PATH="dist/afm-api-macos-arm64.tar.gz"
SHA_PATH="dist/afm-api-macos-arm64.tar.gz.sha256"
[[ -f "$ASSET_PATH" ]] || fail "Missing asset: $ASSET_PATH"
[[ -f "$SHA_PATH" ]] || fail "Missing sha256 file: $SHA_PATH"

tar_listing="$(tar -tzf "$ASSET_PATH" | sort)"
echo "$tar_listing" | rg -x 'afm-api' >/dev/null || fail "Asset is missing afm-api binary."
echo "$tar_listing" | rg -x 'afm-api-server' >/dev/null || fail "Asset is missing afm-api-server binary."
ok "Release asset contains afm-api and afm-api-server."

info "Uploading release assets"
gh release upload "$RELEASE_TAG" "$ASSET_PATH" "$SHA_PATH"

tap_watch_start_epoch="$(date +%s)"
info "Publishing release $RELEASE_TAG"
gh release edit "$RELEASE_TAG" --draft=false

info "Waiting for 'Update Homebrew Tap' workflow"
run_id="$(wait_for_tap_update_run "$tap_watch_start_epoch")"
if [[ -z "$run_id" ]]; then
  warn "Did not detect release-triggered tap update workflow. Dispatching workflow manually."
  gh workflow run "Update Homebrew Tap" --ref main -f release_tag="$RELEASE_TAG"
  sleep 3
  run_id="$(wait_for_tap_update_run "$(date +%s)")"
fi

[[ -n "$run_id" ]] || fail "Could not locate 'Update Homebrew Tap' workflow run."

gh run watch "$run_id"
run_conclusion="$(gh run view "$run_id" --json conclusion --jq .conclusion)"
[[ "$run_conclusion" == "success" ]] || fail "Update Homebrew Tap workflow failed for run $run_id."
ok "Homebrew tap update workflow succeeded (run $run_id)."

if [[ "$SKIP_SMOKE" == "0" ]]; then
  smoke_test_homebrew_release "${RELEASE_TAG#v}"
else
  warn "Skipping Homebrew smoke test (--skip-smoke)."
fi

ok "Stable release $RELEASE_TAG completed successfully."
info "Release URL: https://github.com/tankibaj/apple-foundation-model-api/releases/tag/$RELEASE_TAG"
