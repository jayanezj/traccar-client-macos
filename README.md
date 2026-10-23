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

No location permission request or server connection is part of this shell. Real-Mac UI checks remain distinct from automated compilation. Early CI is tracked in [issue #2](https://github.com/jayanezj/traccar-client-macos/issues/2), before subsequent functionality.

## Artwork

The application and menu-bar icons are derived from the editable SVG in [Artwork](Artwork/README.md). PNG assets are checked in; normal builds require no artwork tooling. The menu-bar image uses system template rendering for light and dark appearances.

## License

[Apache License 2.0](LICENSE). This project is independent of the official Traccar project and does not claim official affiliation.
