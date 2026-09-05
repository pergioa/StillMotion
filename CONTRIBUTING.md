# Contributing to StillMotion

Thank you for taking the time to improve StillMotion. Contributions are welcome through GitHub issues and pull requests.

## Project Governance

The `main` branch is protected and maintained by [@pergioa](https://github.com/pergioa). Contributors work from their own forks and cannot push directly to this repository. Only `@pergioa` can approve and merge pull requests after review and successful automated checks.

Do not request direct write access as part of a contribution. A review may ask for changes, and acceptance is not guaranteed even when automated checks pass.

## Before You Start

- Search existing issues and pull requests to avoid duplicating work.
- Open an issue before beginning a large feature, architectural change, or behavior change.
- Keep each contribution focused on one problem.
- Do not include generated apps, DMGs, ZIPs, DerivedData, or personal Xcode settings.

## Create Your Fork

Fork the repository on GitHub, then clone your fork:

```sh
git clone https://github.com/YOUR-USERNAME/StillMotion.git
cd StillMotion
git remote add upstream https://github.com/pergioa/StillMotion.git
```

Keep your local `main` branch synchronized with the upstream repository:

```sh
git switch main
git fetch upstream
git merge --ff-only upstream/main
git push origin main
```

## Create A Branch

Create every change on a branch in your fork. Use one of these prefixes:

- `feat/<short-description>` for a user-facing feature
- `fix/<short-description>` for a bug fix
- `chore/<short-description>` for maintenance, documentation, tests, or tooling

For example:

```sh
git switch -c fix/full-screen-detection
```

Do not develop directly on `main`.

## Make Your Changes

- Follow the existing Swift and SwiftUI style.
- Prefer small, focused changes over broad rewrites.
- Add or update tests for changed behavior.
- Use public macOS APIs; StillMotion intentionally avoids private CGS and Spaces APIs.
- Preserve sandboxing, privacy, and per-display behavior.
- Add the existing SPDX and copyright header to new Swift source files.
- Update documentation when behavior, requirements, or commands change.

All contributions are submitted under the repository's `GPL-3.0-or-later` license.

## Test Locally

Run the complete Xcode build and test suite:

```sh
xcodebuild -project StillMotion.xcodeproj \
  -scheme StillMotion \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build test
```

You can also run the portable core-logic checks:

```sh
swift run StillMotionLogicChecks
```

Confirm that your working tree contains only the intended changes:

```sh
git status --short
git diff --check
```

## Commit And Push

Use a concise commit subject with the same category as your branch:

```sh
git add <changed-files>
git commit -m "fix: describe the corrected behavior"
git push -u origin fix/full-screen-detection
```

Keep unrelated changes in separate commits or pull requests.

## Open A Pull Request

Open a pull request from your forked branch into `pergioa/StillMotion:main`. Complete the pull request template and describe:

- The problem and intended behavior
- The implementation approach
- Tests performed
- User-interface changes, with screenshots or recordings when relevant

GitHub Actions will build and test the pull request. Address review feedback on the same branch and keep it current with `upstream/main`. Only `@pergioa` will trigger the final merge after approving the contribution and confirming all required checks pass.
