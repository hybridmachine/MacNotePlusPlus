# macOS Code Signing and Notarization Guide

## Overview

PaperWasp supports code signing and notarization for distribution outside the Mac App Store
using Apple's "Developer ID" program. This document covers:

1. Apple Developer account setup
2. Local development signing
3. CI/CD automated signing
4. Troubleshooting

## Prerequisites

### Apple Developer Account

You need an [Apple Developer Program](https://developer.apple.com/programs/) membership ($99/year).
A free Apple Developer account is NOT sufficient for Developer ID signing.

### Required Credentials

| Credential | Where to Get It | Used For |
|---|---|---|
| Developer ID Application certificate | Xcode > Settings > Accounts > Manage Certificates | Signing the .app and .dmg |
| Apple ID | Your Apple account email | Notarization submission |
| Team ID | [Apple Developer > Membership](https://developer.apple.com/account) | Notarization |
| App-specific password | [appleid.apple.com > Security](https://appleid.apple.com/account/manage/section/security) | Notarization API auth |

### Certificate Setup

1. Open Xcode > Settings > Accounts
2. Select your Apple Developer team
3. Click "Manage Certificates..."
4. Click "+" and choose "Developer ID Application"
5. Xcode will create the certificate and install it in your keychain

Verify it is installed:
```bash
security find-identity -v -p codesigning
```

You should see a line like:
```
1) ABCDEF1234... "Developer ID Application: Your Name (TEAMID)"
```

## Local Development Signing

### Build and Sign with CMake

```bash
cd macos/build
rm -rf *
cmake -G Xcode .. \
    -DCODESIGN_ENABLED=ON \
    -DCODESIGN_IDENTITY="Developer ID Application"
cmake --build . --target PaperWasp_sign --config Release
```

The identity "Developer ID Application" (without a specific name) works if you have
exactly one such certificate in your keychain. If you have multiple, specify the full
identity:

```bash
-DCODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
```

### Build Signed DMG

```bash
cmake --build . --target PaperWasp_dmg --config Release
```

When `CODESIGN_ENABLED=ON`, the DMG target will:
1. Build the app bundle
2. Sign the app with hardened runtime and entitlements
3. Create the DMG
4. Sign the DMG
5. Rename from `PaperWasp-unsigned.dmg` to `PaperWasp.dmg`

### Sign and Notarize (Full Workflow)

```bash
export CODESIGN_IDENTITY="Developer ID Application"
export APPLE_ID="your@email.com"
export APPLE_TEAM_ID="ABCDE12345"
export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"

# Build unsigned first
cd macos/build
cmake -G Xcode ..
cmake --build . --target PaperWasp_dmg --config Release

# Sign and notarize
../scripts/sign-and-notarize.sh --verbose
```

### Building WITHOUT Signing (default)

```bash
cd macos/build
cmake -G Xcode ..       # CODESIGN_ENABLED defaults to OFF
cmake --build . --target PaperWasp_dmg --config Release
# Produces: macos/dist/PaperWasp-unsigned.dmg
```

## sign-and-notarize.sh Script

The standalone script at `macos/scripts/sign-and-notarize.sh` handles the full workflow.

### Required Environment Variables

For signing:
- `CODESIGN_IDENTITY` - Signing identity (e.g., "Developer ID Application: Name (TEAMID)")

For notarization (one of two auth modes):

**Password auth:**
- `APPLE_ID` - Apple ID email
- `APPLE_TEAM_ID` - 10-character Team ID
- `APPLE_APP_PASSWORD` - App-specific password

**API key auth:**
- `APPLE_API_KEY` - Key ID from App Store Connect
- `APPLE_API_ISSUER` - Issuer UUID
- `APPLE_API_KEY_PATH` (optional) - Path to `.p8` key file

### Options

| Flag | Description |
|---|---|
| `--app-path PATH` | Path to .app bundle (default: `macos/dist/PaperWasp.app`) |
| `--dmg-path PATH` | Path to .dmg file (auto-detected) |
| `--entitlements PATH` | Path to entitlements (default: `macos/platform/PaperWasp.entitlements`) |
| `--skip-notarize` | Only sign, do not notarize |
| `--skip-dmg` | Only process the .app, not the DMG |
| `--verbose` | Enable verbose output |

## CI/CD Setup (GitHub Actions)

### Required Repository Secrets

Go to your GitHub repository > Settings > Secrets and variables > Actions, and add:

| Secret Name | Value |
|---|---|
| `APPLE_CERTIFICATE_P12` | Base64-encoded .p12 export of your Developer ID Application certificate |
| `APPLE_CERTIFICATE_PASSWORD` | Password used when exporting the .p12 |
| `APPLE_TEAM_ID` | Your 10-character Apple Developer Team ID |
| `APPLE_CODESIGN_IDENTITY` | Full signing identity string (e.g., "Developer ID Application: Your Name (TEAMID)") |
| `APPLE_ID` | Apple ID email for notarytool |
| `APPLE_APP_PASSWORD` | App-specific password for notarytool |

### Exporting the Certificate as Base64

```bash
# Export from Keychain Access:
# 1. Open Keychain Access
# 2. Find "Developer ID Application: ..." in "login" keychain
# 3. Right-click > Export... > Save as .p12 with a password

# Convert to base64 for GitHub secret:
base64 -i DeveloperIDApplication.p12 | pbcopy
# Paste into the APPLE_CERTIFICATE_P12 secret
```

### How CI Signing Works

1. The `build_macos` job builds unsigned artifacts on 3 macOS runners
2. The `sign_and_notarize` job (only on push/workflow_dispatch, not PRs):
   - Downloads the ARM64 app bundle artifact
   - Creates a temporary keychain and imports the .p12 certificate
   - Builds a DMG from the app bundle
   - Runs `sign-and-notarize.sh` to sign, notarize, and staple
   - Uploads signed artifacts (30-day retention)
   - Cleans up the temporary keychain

If signing secrets are not configured, the job skips gracefully with a warning.

## Hardened Runtime Entitlements

The entitlements file is at `macos/platform/PaperWasp.entitlements`.

| Entitlement | Reason |
|---|---|
| `com.apple.security.cs.allow-unsigned-executable-memory` | Scintilla editor component requires this for lexer execution |
| `com.apple.security.cs.disable-library-validation` | Plugin loading via dlopen (Win32 LoadLibrary shim) |

Do NOT add entitlements unless absolutely necessary. Each entitlement weakens the
security posture and may cause notarization warnings.

## Troubleshooting

### "developer cannot be verified" dialog

The app is not notarized, or the ticket is not stapled. Run:
```bash
xcrun stapler staple /path/to/PaperWasp.app
spctl --assess --type execute --verbose /path/to/PaperWasp.app
```

### "code signature invalid"

Re-sign with `--force --deep`:
```bash
codesign --force --options runtime --deep \
    --sign "Developer ID Application" \
    --entitlements macos/platform/PaperWasp.entitlements \
    --timestamp \
    /path/to/PaperWasp.app
```

### Notarization fails with "The signature of the binary is invalid"

Ensure you are signing with `--options runtime` (hardened runtime) and `--timestamp`.

### Notarization fails with "The binary uses an SDK older than the 10.9 SDK"

Rebuild with a current Xcode and SDK. The minimum deployment target (13.0) is fine.

### Checking notarization status

```bash
xcrun notarytool log <submission-id> \
    --apple-id "your@email.com" \
    --team-id "TEAMID" \
    --password "app-specific-password"
```

### "errSecInternalComponent" in CI

The keychain was not unlocked or the partition list was not set. Verify the keychain
setup steps in the CI workflow include `security set-key-partition-list`.
