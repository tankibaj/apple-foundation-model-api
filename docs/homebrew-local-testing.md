# Local Homebrew Testing

This guide explains how to test `afm-api` from your current local branch without merging into `main`.

## Quick Start

From the repo root:

```bash
./tests/test_homebrew_feature_branch_install.sh
```

Default tap used by the test script:

- `tankibaj/localtap`

## What The Test Does

1. Creates a tarball from current `HEAD`.
2. Creates/uses the local tap (`tankibaj/localtap` by default).
3. Writes a temporary formula for `afm-api`.
4. Runs:
   - `brew reinstall --build-from-source tankibaj/localtap/afm-api`
5. Runs a smoke test:
   - `afm-api --rebuild --background`
   - `curl http://127.0.0.1:8000/v1/health`
   - `afm-api --stop`
6. Cleans up temporary artifacts by default.

## Optional Flags

Keep installed formula:

```bash
KEEP_INSTALL=1 ./tests/test_homebrew_feature_branch_install.sh
```

Keep local tap:

```bash
KEEP_TAP=1 ./tests/test_homebrew_feature_branch_install.sh
```

Use a custom local tap:

```bash
./tests/test_homebrew_feature_branch_install.sh myuser/localtap
```

## Manual Cleanup

```bash
afm-api --stop || true
brew uninstall afm-api || true
brew uninstall tankibaj/localtap/afm-api || true
brew untap tankibaj/localtap || true
rm -f /tmp/afm-api-feature-*.tar.gz
rm -rf /tmp/afm-api
```

Optional cleanup for published tap install:

```bash
brew untap tankibaj/tap || true
```
