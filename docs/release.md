# Stable Release Process (Prebuilt Binary)

This project ships **stable** Homebrew releases as prebuilt binaries.

## Why Manual Binary Release

Apple Foundation Models compilation is not reliably available on GitHub-hosted runners for this repo runtime target.

To guarantee stable installs do not build Swift on user machines:

- Stable release binaries are built locally on a compatible macOS environment.
- The release asset must contain both `afm-api` and `afm-api-server`.
- Homebrew installs those binaries directly.

## One-Command Stable Release

From repository root on `main`:

```bash
./scripts/release_binary.sh
```

Optional version controls:

```bash
./scripts/release_binary.sh --bump minor
./scripts/release_binary.sh --version v1.3.0
```

## What The Script Does

1. Validates local state:
- clean git working tree
- current branch is `main`
- local `main` matches `origin/main`

2. Validates build environment:
- macOS >= 26.0
- Swift toolchain present
- Xcode CLT present

3. Creates and pushes new stable tag.
4. Creates draft GitHub release for the tag.
5. Builds prebuilt asset with **source fallback disabled**.
6. Verifies tarball contains:
- `afm-api`
- `afm-api-server`

7. Uploads assets to the release.
8. Publishes the release.
9. Waits for `Update Homebrew Tap` workflow success.
10. Runs Homebrew smoke test:
- `brew reinstall tankibaj/tap/afm-api`
- verifies installed version
- verifies `afm-api-server` exists on PATH
- starts server in background
- checks `GET /v1/health`
- stops server

## Notes

- Stable releases always use a new semver tag (`vX.Y.Z`).
- Do not overwrite stable assets for existing tags.
- If smoke test fails, treat release as failed and fix forward with a new patch release.
