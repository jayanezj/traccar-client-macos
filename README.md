# Traccar Client for macOS

An independent, unofficial native Traccar client for Apple Silicon Macs.

**Development status:** local configuration and identity persistence for [issue #3](https://github.com/jayanezj/traccar-client-macos/issues/3). This build stays paused. Location access, tracking and position/SOS delivery are not implemented; their menu actions are disabled.

## Requirements

- Apple Silicon, starting with M1.
- macOS 15.0 or later. Deployment target 15.0 does not by itself establish runtime test coverage.
- Stable Xcode 27.1 for the initial development toolchain; Swift 6 language mode.

## Build and run

Local builds use a free **Apple Development** certificate and a Personal Team; a paid Apple Developer Program subscription is not required. In Xcode → Settings → Apple Accounts, add your Apple Account, select the Personal Team and create an Apple Development certificate in Manage Certificates if needed. Keep the certificate's private key in Keychain.

Copy `Configuration/Signing.local.xcconfig.example` to `Configuration/Signing.local.xcconfig` and replace `YOUR_TEAM_ID` with your own Personal Team ID. The local file is ignored by Git. If several certificates match, optionally select the certificate's SHA-1 identifier there. Never put a private key, password or signing archive in either file. The shared signing settings apply to the app and test target in Debug and Release; missing credentials fail the build rather than silently switching signing mode.

Open `TraccarClient.xcodeproj`, select the shared **TraccarClient** scheme and run the macOS target. Set Xcode's Derived Data and Archives locations to your external development volume before building if internal storage is limited.

For a terminal build, supply an absolute build directory on that volume:

```sh
scripts/build.sh /path/to/external/build-directory Debug
```

Replace the example path with your actual directory. The app is produced at `DerivedData/Build/Products/Debug/Traccar Client macOS.app` beneath it. Use `Release` instead of `Debug` for an optimized build. The shared scheme also supports archiving; configure Xcode's archive location separately.

The app currently uses no provisioning profile or restricted entitlements. Apple Development is a development identity, not Developer ID, and the app is not notarized. The selected distribution plan is a DMG containing the Apple Development-signed app; installation on another Mac and Gatekeeper authorization remain to be validated in [issue #16](https://github.com/jayanezj/traccar-client-macos/issues/16). Creating a DMG does not grant Gatekeeper approval. Protected release signing will be addressed in [issue #17](https://github.com/jayanezj/traccar-client-macos/issues/17); it is not part of the ordinary PR workflow.

## Initial shell smoke check

1. Launch the built app. It should show a menu-bar icon and paused status. The Dock icon appears while Settings or About is open and disappears after the last window closes.
2. Confirm Start tracking, Send location now and Send SOS are disabled.
3. Open Settings and switch to another app. Confirm Traccar Client is available in Command-Tab and the Dock. Minimize Settings and recover it from the Dock. Open About too: closing one window should keep the Dock icon; closing the last should hide it while the process and menu-bar icon remain running. Reopen Settings from the menu.
4. Open About and check the version, unofficial-client statement and Apache-2.0 license information.
5. Quit from the menu. The process should terminate.

No location permission request or server connection is part of this shell. Real-Mac UI checks remain distinct from automated compilation.

## Local configuration

Open Settings from the menu bar. Configuration loads automatically with a noninteractive Keychain read when access is already available, or on a fresh installation. Only when authorization is needed does the explanation and **Access Keychain** button appear. Cancelling requires an explicit **Retry loading**; closing and reopening Settings does not repeat the denied request automatically. Once loaded, save the receiver URL, identifier and tracking preferences. The initial URL is the Traccar public demo, `http://demo.traccar.org:5055`. HTTP and HTTPS support IP addresses (including IPv6), domains, optional ports, paths and query parameters. Validation is local; embedded credentials and URL fragments are rejected. Use the protocol receiver URL, which can differ from the server's web interface.

Enter an existing identifier exactly, including leading zeros, to continue that device's history. Leaving it blank generates eight random digits on save, displays the value and persists it for reuse. This does not register a device: add the identifier in Traccar separately. Random identifiers are not guaranteed globally unique.

The receiver URL and identifier share one Keychain item, protecting any sensitive query parameters. Tracking preferences use a versioned UserDefaults record. macOS may request the login keychain password; the app never receives that password. The system dialog offers Allow, Always Allow or Deny. Always Allow applies to the recognized application. Keep the same Personal Team and compatible signing identity across updates. Moving from an ad hoc build or another identity may require authorization again. Continuity with the same Apple Development certificate has been checked manually; continuity after certificate renewal remains an untested assumption, not a guarantee. Cancelling reports that stored configuration is unchanged and leaves access available through **Retry loading**, with no automatic retries. Keychain errors are displayed; there is no plaintext fallback. Unreadable settings or a missing saved identity block saving until loading succeeds, rather than silently replacing the identity. Retry loading after resolving the storage problem. A generated identifier remains visible after a failed save so a retry reuses it.

Defaults are medium accuracy, 300 seconds, 75 metres, zero angle/heartbeat, buffering enabled and stationary detection enabled. Time OR distance will select positions when tracking is implemented. Launch-at-login and tracking restoration remain off and their controls are disabled. Loading and saving never request location, start tracking or contact a receiver. Editable fields have visible borders and explicit labels; informational notices use an information icon. Loaded/saved status messages disappear after ten seconds, with the timer restarting for a new message. The footer reserves a fixed message area so showing or hiding status does not resize the form. Errors remain visible until resolved.

### Configuration smoke check

Use a synthetic identifier and a test receiver URL; no receiver is contacted in this build.

1. Open Settings. With an accessible Keychain item or a fresh configuration, confirm Settings loads directly without an extra button or prompt. If authorization is required, confirm the explanation appears first; cancel the system dialog and verify the cancellation message and absence of automatic retries. With another app behind Settings, deny access twice using Retry loading and check that Settings returns to the foreground with keyboard focus each time. Then authorize access if desired. Confirm the public-demo notice and default tracking values on a fresh configuration.
2. Leave the identifier blank and save. Confirm an eight-digit identifier appears.
3. Quit and reopen the app. Open Settings and authorize only if requested. Confirm URL, identifier and tracking preferences remain saved and status remains paused.
4. Save an identifier such as `000123-test`, then quit and reopen. Confirm it is preserved exactly.
5. Try an invalid URL such as `ftp://example.com`. Saving should report an error and preserve the last saved configuration.
6. Confirm no location permission request or network request occurs. Check real Keychain access and Settings reopening separately from the isolated automated suite.

## Continuous integration

The workflow in `.github/workflows/ci.yml` runs on pull requests, pushes to `main` and manual dispatch. It exposes three checks:

| Check | Runner | Toolchain | Work |
| --- | --- | --- | --- |
| SwiftLint | `macos-15` arm64 | Xcode 26.3; SwiftLint 0.65.1 | Strict lint, including warnings |
| Build (primary) | `xcode-27` arm64 | Xcode 27.1, build 27A9275; macOS SDK 27.0 | Debug, Release and configuration tests |
| Build (macOS 15) | `macos-15` arm64 | Xcode 26.3, build 17C529; macOS SDK 26.2 | Debug, Release and configuration tests |

Both build jobs explicitly set `TRACCAR_SIGNING_MODE=adhoc`: CI builds and tests need no Apple account or private signing key, including for fork PRs. These builds are validation artifacts, not distribution packages. Local builds default to `development` and use Apple Development. Signature verification checks the selected mode explicitly.

Both build jobs verify the host architecture, OS major version, selected Xcode/build and SDK before compiling. They also verify arm64 binaries, deployment target 15.0 and application signatures. A missing or unexpected toolchain fails the check. The `xcode-27` runner image is a public preview, accepted for early CI; Xcode 27.1 build 27A9275 itself is an Apple final release. Review the runner's status before automating releases.

Both build jobs execute the hostless Swift Testing target. It compiles the same configuration sources as the application and tests validation, stable identity generation, save/reload, storage errors, transient status expiry/cancellation and the guard for future pending-position checks. Window-focus tests cover deferred activation, closed/minimized windows, activation failure and superseded requests. Tests use isolated UserDefaults suites, synthetic Keychain operations and fake windows/activation; they do not open the app, use the login Keychain or contact a server. A narrowly scoped legacy Keychain API suppresses interaction during the initial file-based read and immediately restores its previous setting. All application Keychain operations run synchronously on the main actor. The modern LAContext interaction flags do not suppress the legacy file-based dialogs. Real Keychain access, UI relaunch, location permissions, sleep behaviour and Gatekeeper require separate checks. Subsequent features extend this suite in the same PR as their implementation.

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

The default signing mode is `development` and requires the local Apple Development setup above. To run the credential-free CI signing mode explicitly, use a separate validation directory:

```sh
TRACCAR_SIGNING_MODE=adhoc scripts/check-local.sh /path/to/external/local-ci-adhoc
```

`TRACCAR_SIGNING_MODE` also applies to the individual build, test and verification scripts. Accepted values are `development` and `adhoc`; there is no automatic fallback. The ad hoc mode is for CI validation, not for producing the selected distribution build.

The command checks the toolchain, shell syntax and whitespace in staged/unstaged tracked changes, runs strict SwiftLint, builds Debug and Release, runs configuration tests, then verifies both binaries' architecture, deployment target and the selected signing mode. It stops at the first failure and returns a nonzero exit code. Tools are cached under `tools/` and incremental build products under `build/` in the supplied directory. The toolchain, lint, build, test and binary verification scripts are shared with CI. Test result bundles are saved under `build/TestResults/`, with a unique directory per run.

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

The script downloads the official portable SwiftLint release, verifies its pinned SHA-256 and checks the executable version. `.swiftlint.yml` applies the default rules to application and test sources, with mandatory trailing commas in multiline collections. No baseline or automatic fixes are applied. SwiftLint is a development tool, not an application package dependency.

Run configuration tests alone with Xcode or the shared script:

```sh
scripts/test.sh /path/to/external/build-directory
```

In Xcode, choose the shared TraccarClient scheme and Product → Test. A failed assertion makes the script and CI job fail. CI retains sanitized text diagnostics on failure; `.xcresult` bundles remain local to the runner. Test fixtures contain only synthetic values and clean up their isolated preferences.

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
