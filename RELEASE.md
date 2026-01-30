# Distribute GitHub Actions Menu App

## Prerequisites (manual, not code changes)

1. **Apple Developer Program** — enroll at developer.apple.com ($99/year). Required for both direct download and Mac App Store.
2. **Certificates** — create in Xcode or Apple Developer portal:
   - **Developer ID Application** — for direct download distribution
   - **Mac App Distribution** + **Mac Installer Distribution** — for Mac App Store
3. **App ID** — register `com.menuapp.github-actions` (or a new bundle ID) in the Developer portal with capabilities: Keychain Sharing, Push Notifications.
4. **Provisioning Profile** — for Mac App Store distribution (not needed for Developer ID).

---

## Code Changes

### 1. Create `Resources/GitHubActionsMenu.entitlements`

Production entitlements file (used for both distribution methods):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>keychain-access-groups</key>
    <array>
        <string>$(AppIdentifierPrefix)com.menuapp.github-actions</string>
    </array>
</dict>
</plist>
```

- `app-sandbox` — required for Mac App Store, recommended for Developer ID
- `network.client` — outbound HTTPS to `api.github.com`
- `keychain-access-groups` — for storing the GitHub PAT

### 2. Update `Makefile`

Add new targets for production signing, notarization, and DMG creation:

- `release` target: build + bundle + sign with Developer ID + hardened runtime + entitlements
- `notarize` target: submit to Apple notary service via `xcrun notarytool`
- `dmg` target: create a distributable .dmg

Key codesign change:
```
codesign --force --sign "Developer ID Application: YOUR NAME (TEAM_ID)" \
    --options runtime \
    --entitlements Resources/GitHubActionsMenu.entitlements \
    $(APP_BUNDLE)
```

### 3. Update `Resources/Info.plist`

Add `NSHumanReadableCopyright` key (shown in Finder "Get Info"):
```xml
<key>NSHumanReadableCopyright</key>
<string>Copyright © 2025 Your Name. All rights reserved.</string>
```

---

## Distribution: Direct Download

After the code changes above:

1. `make release` — builds, bundles, signs with Developer ID + hardened runtime
2. `make dmg` — packages into a .dmg
3. `make notarize` — submits to Apple notary, staples the ticket
4. Upload the .dmg to GitHub Releases

Users can download, drag to Applications, and open without Gatekeeper warnings.

## Distribution: Mac App Store

Additional steps beyond code changes:

1. Create the app in **App Store Connect** (appstoreconnect.apple.com)
2. Add screenshots, description, privacy policy URL, category
3. Sign with **Mac App Distribution** certificate instead of Developer ID
4. Upload via `xcrun altool --upload-app` or Transporter.app
5. Submit for App Review

---

## Verification

1. Run `make release` — should build and codesign with real certificate
2. Run `codesign -dvvv GitHubActionsMenu.app` — verify signing identity and entitlements
3. Run `spctl --assess --type execute GitHubActionsMenu.app` — should say "accepted" after notarization
4. Test on a separate Mac (or a fresh user account) to confirm Gatekeeper doesn't block it
