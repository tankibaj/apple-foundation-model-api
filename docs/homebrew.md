# Homebrew Guide

## End Users

Install:

```bash
brew tap tankibaj/tap
brew install afm-api
```

Update:

```bash
brew update
brew upgrade afm-api
```

Verify:

```bash
afm-api --version
which afm-api
which afm-api-server
```

## Local Tap Testing (Feature Branch)

Use:

```bash
./tests/homebrew_feature_branch_install.sh
```

Full details: [homebrew-local-testing.md](./homebrew-local-testing.md)
