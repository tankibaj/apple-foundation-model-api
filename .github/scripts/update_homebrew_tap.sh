#!/usr/bin/env bash
set -euo pipefail

RELEASE_TAG="${RELEASE_TAG:-${1:-}}"
TAP_REPO_PATH="${TAP_REPO_PATH:-${2:-}}"
RELEASE_ASSET_FILE="${RELEASE_ASSET_FILE:-}"
RELEASE_ASSET_NAME="${RELEASE_ASSET_NAME:-afm-api-macos-arm64.tar.gz}"
RELEASE_ASSET_URL="${RELEASE_ASSET_URL:-}"
REPO_SLUG="${REPO_SLUG:-tankibaj/apple-foundation-model-api}"
FORMULA_NAME="${FORMULA_NAME:-afm-api}"

if [[ -z "${RELEASE_TAG}" || -z "${TAP_REPO_PATH}" ]]; then
  echo "Usage: RELEASE_TAG=v1.0.2 TAP_REPO_PATH=/path/to/homebrew-tap $0"
  exit 1
fi

if [[ ! "${RELEASE_TAG}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: RELEASE_TAG must match v<major>.<minor>.<patch>, got: ${RELEASE_TAG}"
  exit 1
fi

if [[ ! -d "${TAP_REPO_PATH}/Formula" ]]; then
  echo "ERROR: ${TAP_REPO_PATH}/Formula not found"
  exit 1
fi

VERSION="${RELEASE_TAG#v}"
MAJOR_MINOR="$(echo "${VERSION}" | cut -d. -f1,2)"
URL="${RELEASE_ASSET_URL:-https://github.com/${REPO_SLUG}/releases/download/${RELEASE_TAG}/${RELEASE_ASSET_NAME}}"
BASE_FORMULA_PATH="${TAP_REPO_PATH}/Formula/${FORMULA_NAME}.rb"
VERSIONED_FORMULA_PATH="${TAP_REPO_PATH}/Formula/${FORMULA_NAME}@${MAJOR_MINOR}.rb"

if [[ ! -f "${BASE_FORMULA_PATH}" ]]; then
  echo "ERROR: base formula not found: ${BASE_FORMULA_PATH}"
  exit 1
fi

TMP_ASSET=""
if [[ -n "${RELEASE_ASSET_FILE}" ]]; then
  if [[ ! -f "${RELEASE_ASSET_FILE}" ]]; then
    echo "ERROR: RELEASE_ASSET_FILE not found: ${RELEASE_ASSET_FILE}"
    exit 1
  fi
  TMP_ASSET="${RELEASE_ASSET_FILE}"
else
  TMP_ASSET="$(mktemp -t afm-api-release-XXXXXX.tar.gz)"
  curl -fsSL "${URL}" -o "${TMP_ASSET}"
fi

SHA256="$(shasum -a 256 "${TMP_ASSET}" | awk '{print $1}')"

FORMULA_CLASS_BASE="AfmApi"
FORMULA_CLASS_VERSIONED="AfmApiAT${MAJOR_MINOR//./}"

update_formula_file() {
  local file_path="$1"
  local class_name="$2"

  ruby - "${file_path}" "${class_name}" "${URL}" "${SHA256}" "${VERSION}" <<'RUBY'
path, class_name, url, sha, version = ARGV
content = File.read(path)
content.sub!(/^class\s+\S+\s+<\s+Formula$/, "class #{class_name} < Formula")
content.sub!(/^\s*url\s+".*"$/, "  url \"#{url}\"")
content.sub!(/^\s*sha256\s+".*"$/, "  sha256 \"#{sha}\"")
if content.match?(/^\s*version\s+"/)
  content.sub!(/^\s*version\s+".*"$/, "  version \"#{version}\"")
else
  content.sub!(/^\s*url\s+".*"$/, "  url \"#{url}\"\n  version \"#{version}\"")
end
File.write(path, content)
RUBY
}

update_formula_file "${BASE_FORMULA_PATH}" "${FORMULA_CLASS_BASE}"

if [[ ! -f "${VERSIONED_FORMULA_PATH}" ]]; then
  cp "${BASE_FORMULA_PATH}" "${VERSIONED_FORMULA_PATH}"
fi
update_formula_file "${VERSIONED_FORMULA_PATH}" "${FORMULA_CLASS_VERSIONED}"

echo "Updated: ${BASE_FORMULA_PATH}"
echo "Updated: ${VERSIONED_FORMULA_PATH}"
echo "Release: ${RELEASE_TAG}"
echo "SHA256: ${SHA256}"
