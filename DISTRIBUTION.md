# Distribution Guide — TranscribeMini

How to build, sign, notarize, and distribute TranscribeMini as a proper macOS app.

## Prerequisites

- Xcode command line tools: `xcode-select --install`
- Active Apple Developer account (Team ID: `3E7SN2D98G`)

---

## Step 1 — Create a Developer ID Certificate

You need a **Developer ID Application** certificate to sign the app for distribution outside the App Store.

1. Open [developer.apple.com/account](https://developer.apple.com/account)
2. Go to **Certificates, Identifiers & Profiles → Certificates**
3. Click **+** → choose **Developer ID Application**
4. Follow the CSR instructions (Keychain Access → Certificate Assistant → Request a Certificate from a Certificate Authority)
5. Download the `.cer` file and double-click to install into your Keychain

Verify it's installed:
```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

You should see something like:
```
1) XXXXXXXXXXXX "Developer ID Application: Your Name (3E7SN2D98G)"
```

---

## Step 2 — Set Up Notarization Credentials

Notarization is required so users aren't blocked by Gatekeeper.

### Option A — Keychain profile (recommended, one-time setup)

```bash
xcrun notarytool store-credentials "transcribe-notary" \
  --apple-id "your@apple.id" \
  --team-id "3E7SN2D98G" \
  --password "xxxx-xxxx-xxxx-xxxx"   # app-specific password (see below)
```

Get an **app-specific password** at [appleid.apple.com](https://appleid.apple.com) → Sign-In & Security → App-Specific Passwords.

Test credentials work:
```bash
xcrun notarytool history --keychain-profile "transcribe-notary"
```

### Option B — Environment variables (CI/scripting)

```bash
export APPLE_ID="your@apple.id"
export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
export APPLE_TEAM_ID="3E7SN2D98G"
```

---

## Step 3 — Build the App Bundle

```bash
cd ~/Projects/transcribe
bash scripts/build-app-bundle.sh
```

Output: `dist/TranscribeMini.app`

You can set a specific version:
```bash
APP_VERSION=1.0.0 bash scripts/build-app-bundle.sh
```

---

## Step 4 — Sign & Notarize

### With keychain profile (Option A):
```bash
NOTARY_KEYCHAIN_PROFILE="transcribe-notary" bash scripts/sign-and-notarize-app.sh
```

### With environment variables (Option B):
```bash
bash scripts/sign-and-notarize-app.sh
# (APPLE_ID, APPLE_APP_PASSWORD, APPLE_TEAM_ID must be set)
```

This script will:
1. Sign the app with your Developer ID certificate
2. Zip it and submit to Apple for notarization (takes ~1–5 minutes)
3. Staple the notarization ticket to the app
4. Verify Gatekeeper accepts it

Output: `dist/TranscribeMini.app` (signed + notarized) and `dist/TranscribeMini.zip`

---

## Step 5 — Distribute

### Via Homebrew Cask (recommended)

The repo includes a Homebrew cask template in `packaging/homebrew/`.

1. Get the SHA256 from the sign-and-notarize output
2. Update the cask file with the new version + SHA256
3. Push to your tap (or submit to `homebrew/cask` if you want public listing)

Users can then install with:
```bash
brew install --cask transcribemini
```

### Direct download

Just share the `dist/TranscribeMini.zip`. Since it's notarized, users can open it without any Gatekeeper warnings.

---

## Full Release Checklist

- [ ] Developer ID Application certificate installed in Keychain
- [ ] App-specific password created at appleid.apple.com
- [ ] Notarization credentials stored: `xcrun notarytool store-credentials "transcribe-notary" ...`
- [ ] `bash scripts/build-app-bundle.sh` — builds `dist/TranscribeMini.app`
- [ ] `NOTARY_KEYCHAIN_PROFILE="transcribe-notary" bash scripts/sign-and-notarize-app.sh` — signs + notarizes
- [ ] Gatekeeper check passes: `spctl --assess --type execute --verbose dist/TranscribeMini.app`
- [ ] Update Homebrew cask with new version + SHA256
- [ ] Tag the release: `git tag v1.0.0 && git push --tags`

---

## Troubleshooting

**"No identity found" during signing**
→ Certificate isn't in Keychain. Repeat Step 1.

**Notarization fails with "invalid credentials"**
→ Re-create the app-specific password and re-run `notarytool store-credentials`.

**Gatekeeper still blocks after notarization**
→ Make sure `xcrun stapler staple` ran successfully. Re-run the sign script.

**App crashes on launch after signing**
→ Check entitlements. Microphone + Accessibility access may need explicit entitlements in a `.entitlements` file for hardened runtime.
