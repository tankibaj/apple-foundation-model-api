#!/usr/bin/env bash
set -euo pipefail

latest_tag="$(git tag --list 'v*' | sort -V | tail -n 1)"
if [[ -z "$latest_tag" ]]; then latest_tag="v0.0.0"; fi

if [[ "$latest_tag" == "v0.0.0" ]]; then
  commits="$(git log --pretty=%B)"
else
  commits="$(git log "${latest_tag}..HEAD" --pretty=%B)"
fi

major=0
minor=0
patch=0
if echo "$commits" | grep -Eq 'BREAKING CHANGE|^[a-zA-Z]+\([^)]+\)!:|^[a-zA-Z]+!:'; then
  major=1
elif echo "$commits" | grep -Eq '^feat(\([^)]+\))?:'; then
  minor=1
elif echo "$commits" | grep -Eq '^(fix|chore|docs|refactor|perf|test|build|ci)(\([^)]+\))?:'; then
  patch=1
else
  patch=1
fi

base="${latest_tag#v}"
IFS='.' read -r vmajor vminor vpatch <<< "$base"
vmajor=${vmajor:-0}
vminor=${vminor:-0}
vpatch=${vpatch:-0}

if [[ "$major" -eq 1 ]]; then
  vmajor=$((vmajor + 1)); vminor=0; vpatch=0
elif [[ "$minor" -eq 1 ]]; then
  vminor=$((vminor + 1)); vpatch=0
else
  vpatch=$((vpatch + 1))
fi

next_tag="v${vmajor}.${vminor}.${vpatch}"

echo "PASS: release version logic"
echo "  latest_tag=$latest_tag"
echo "  next_tag=$next_tag"
