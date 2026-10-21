# ActionBar

Monitor your GitHub Actions workflow runs directly from the macOS menu bar.

<p align="center">
  <img src="docs/screenshot.png" alt="ActionBar showing GitHub Actions workflow runs in the macOS menu bar" width="480">
</p>

<p align="center">
  <a href="https://apps.apple.com/us/app/actionbar/id6758538752">Download on the Mac App Store</a> ·
  <a href="https://ptrchm.com/actionbar/">Website</a>
</p>

## Features

- See workflow run statuses at a glance
- Get notifications when runs complete
- Select the repositories you want to monitor
- Minimal permissions — no access to your code
- Native macOS app — lightweight and fast

## How it works

ActionBar signs in through a [GitHub App](https://github.com/apps/actionbar-macos) using the OAuth device flow. The app only has **Actions (read)** and **Metadata (read)** permissions, so it never has access to your code. It only calls the [workflow runs API](https://docs.github.com/en/rest/actions/workflow-runs) (`/repos/{owner}/{repo}/actions/runs`) for the repositories you select.

Your access token is stored in the macOS Keychain.

By default, ActionBar polls the API every 30 seconds; the interval is configurable, and you can refresh manually at any time. Each monitored repository requires a separate API call on every refresh, so monitoring a large number of repositories may hit GitHub's rate limits.

## Privacy

ActionBar does not collect, transmit, or share any personal data. All communication is exclusively with GitHub's official API (`api.github.com`). No analytics, telemetry, or third-party services are used. All stored data is deleted when you sign out.

## Building from source

Requirements: macOS 14+ and a recent version of Xcode.

1. Clone the repository.
2. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set your Apple Developer Team ID and a bundle identifier registered to your team.
3. Open `ActionBar.xcodeproj` and run the `ActionBar` scheme, or use `make run`.

The app authenticates through the official ActionBar GitHub App. If you're shipping your own fork, register your own [GitHub App](https://docs.github.com/en/apps/creating-github-apps) with device flow enabled and **Actions (read)** permission, then update `clientID` in `Sources/ActionBar/Services/OAuthService.swift` and the app's installation URL.

## License

The source code is released under the [MIT License](LICENSE).

The ActionBar name and app icon are not covered by the license. If you distribute a fork, please use a different name and icon.

ActionBar is an independent project and is not affiliated with GitHub.
