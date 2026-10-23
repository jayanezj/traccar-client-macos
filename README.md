# Traccar Client for macOS

An independent, unofficial native Traccar client for Apple Silicon Macs.

**Development status:** initial application shell for [issue #1](https://github.com/jayanezj/traccar-client-macos/issues/1). This build stays paused. Location access, tracking, server configuration and position/SOS delivery are not implemented; their menu actions are disabled.

## Requirements

- Apple Silicon, starting with M1.
- macOS 15.0 or later. Deployment target 15.0 does not by itself establish runtime test coverage.
- Stable Xcode 27.1 for the initial development toolchain; Swift 6 language mode.

## Build and run

Open `TraccarClient.xcodeproj`, select the shared **TraccarClient** scheme and run the macOS target. Set Xcode's Derived Data and Archives locations to your external development volume before building if internal storage is limited.

For a terminal build, supply an absolute build directory on that volume:

```sh
scripts/build.sh /path/to/external/build-directory Debug
```

Replace the example path with your actual directory. The app is produced at `DerivedData/Build/Products/Debug/Traccar Client macOS.app` beneath it. Use `Release` instead of `Debug` for an optimized build. The shared scheme also supports archiving; configure Xcode's archive location separately.

The app uses ad hoc signing, with no Apple developer account, provisioning profile or paid certificate. It is not notarized. Downloaded application Gatekeeper behaviour and DMG installation will be validated in [issue #16](https://github.com/jayanezj/traccar-client-macos/issues/16).

## Initial shell smoke check

1. Launch the built app. It should show a menu-bar icon, no permanent Dock icon and a paused status.
2. Confirm Start tracking, Send location now and Send SOS are disabled.
3. Open Settings, close its window and reopen it from the menu. The process should remain running.
4. Open About and check the version, unofficial-client statement and Apache-2.0 license information.
5. Quit from the menu. The process should terminate.

No location permission request or server connection is part of this shell. Real-Mac UI checks remain distinct from automated compilation.

## Continuous integration

The workflow in `.github/workflows/ci.yml` runs on pull requests, pushes to `main` and manual dispatch. It exposes three checks:

| Check | Runner | Toolchain | Work |
| --- | --- | --- | --- |
| SwiftLint | `macos-15` arm64 | Xcode 26.3; SwiftLint 0.65.1 | Strict lint, including warnings |
| Build (primary) | `xcode-27` arm64 | Xcode 27.1, build 27A9275; macOS SDK 27.0 | Debug and Release |
| Build (macOS 15) | `macos-15` arm64 | Xcode 26.3, build 17C529; macOS SDK 26.2 | Debug and Release |

Both build jobs verify the host architecture, OS major version, selected Xcode/build and SDK before compiling. They also verify arm64 binaries, deployment target 15.0 and application signatures. A missing or unexpected toolchain fails the check. The `xcode-27` runner image is a public preview, accepted for early CI; Xcode 27.1 build 27A9275 itself is an Apple final release. Review the runner's status before automating releases.

This stage performs lint and compilation only: there is no test target yet. Configuration tests start with [issue #3](https://github.com/jayanezj/traccar-client-macos/issues/3); subsequent features extend this workflow with meaningful tests. Builds do not validate location permissions, sleep behaviour or Gatekeeper.

### Local checks before pushing

Run all local checks with one command, supplying an absolute validation directory outside the repository, preferably on your external development volume:

```sh
scripts/check-local.sh /path/to/external/local-ci
```

Replace the example with your actual path. The default `primary` profile requires macOS 27 arm64, Xcode 27.1 build 27A9275 and SDK 27.0. The script uses the Xcode selected by `xcode-select`, or the `DEVELOPER_DIR` environment variable if set. To select a particular installation without changing the system selection:

```sh
DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer \
  scripts/check-local.sh /path/to/external/local-ci
```

The command checks the toolchain, shell syntax and whitespace in staged/unstaged tracked changes, runs strict SwiftLint, builds Debug and Release, then verifies both binaries' architecture, deployment target and signatures. It stops at the first failure and returns a nonzero exit code. Tools are cached under `tools/` and incremental build products under `build/` in the supplied directory. The toolchain, lint, build and binary verification scripts are shared with CI.

On a separate macOS 15 arm64 environment with Xcode 26.3 build 17C529 and SDK 26.2, select the minimum-system profile explicitly:

```sh
scripts/check-local.sh /path/to/external/local-ci-macos15 macos15
```

Profiles verify the actual machine and toolchain; they do not emulate another macOS version. This command does not reproduce GitHub's clean hosted environment, triggers, permissions or artifact uploads. It does not launch the application; perform the manual smoke check separately. A successful local run does not establish hosted CI or minimum-OS runtime coverage.

### Individual checks

Run the same lint locally, using an absolute tools directory outside the repository:

```sh
scripts/lint.sh /path/to/external/tools-directory
```

The script downloads the official portable SwiftLint release, verifies its pinned SHA-256 and checks the executable version. `.swiftlint.yml` applies the default rules to application sources, with mandatory trailing commas in multiline collections. No baseline or automatic fixes are applied. SwiftLint is a development tool, not an application package dependency.

For a matching machine, reproduce the main toolchain check with:

```sh
scripts/verify-toolchain.sh 27.1 27A9275 27.0 27
```

CI uses read-only repository permissions, Actions pinned to full commit SHAs, bounded timeouts and cancellation of superseded runs. Checkout does not persist credentials. It requires no production secrets or Apple account and does not run the application or send positions. Failed builds retain only text diagnostics, with workspace, temporary and home paths replaced, for seven days; app bundles and build caches are not uploaded.

Swift analysis in SonarQube requires Developer Edition, so SonarQube Community is not a required check. CycloneDX SBOM publication to Dependency-Track is deferred until the application has external dependencies; include it in release automation when applicable.

## Artwork

The application and menu-bar icons are derived from the editable SVG in [Artwork](Artwork/README.md). PNG assets are checked in; normal builds require no artwork tooling. The menu-bar image uses system template rendering for light and dark appearances.

## License

[Apache License 2.0](LICENSE). This project is independent of the official Traccar project and does not claim official affiliation.
