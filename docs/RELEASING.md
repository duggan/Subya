# Releasing Subya

Releases are built, signed, notarized and published by
`.github/workflows/release.yml`, which runs `make release` on a GitHub macOS runner.
GitHub needs four repository secrets to do that. You set them once; GitHub can't show
them to anyone afterwards, including you.

| Secret | What it is |
|---|---|
| `DEVELOPER_ID_CERT_P12` | Your Developer ID Application certificate and its private key, exported as a .p12 file, base64-encoded |
| `DEVELOPER_ID_CERT_PASSWORD` | The password you choose when exporting that .p12 |
| `NOTARY_APPLE_ID` | The Apple ID email used for notarization |
| `NOTARY_PASSWORD` | An app-specific password for that Apple ID (not your real Apple ID password) |

The team ID (`PSPQTHW392`) and signing identity come from the `Makefile`.

## 1. Export the signing certificate

1. Open **Keychain Access**, choose the **login** keychain, then **My Certificates**.
2. Find **Developer ID Application: Ross Duggan (PSPQTHW392)**. Click the disclosure
   triangle to check there's a private key under it; without one, the export is useless.
3. Right-click the certificate (not the key) and choose **Export…**. Pick the
   **Personal Information Exchange (.p12)** format and save it somewhere temporary,
   such as `~/Desktop/developer-id.p12`.
4. Set a strong password when asked. That's `DEVELOPER_ID_CERT_PASSWORD`; keep it in
   your password manager.

If you kept the .p12 and password you made for NanoNeo, you can reuse them.

## 2. Make an app-specific password

1. Sign in at [account.apple.com](https://account.apple.com) and open
   **Sign-In and Security › App-Specific Passwords**.
2. Add one with a name like `Subya GitHub notarization`, and copy the password it
   shows (`xxxx-xxxx-xxxx-xxxx`). That's `NOTARY_PASSWORD`.

A separate password per project means you can revoke one without breaking the others.

## 3. Add the secrets to GitHub

Run these yourself in Terminal. `gh secret set` without `--body` asks for the value
at a hidden prompt, so it never lands in your shell history.

```sh
base64 -i ~/Desktop/developer-id.p12 | gh secret set DEVELOPER_ID_CERT_P12 --repo duggan/Subya
gh secret set DEVELOPER_ID_CERT_PASSWORD --repo duggan/Subya
gh secret set NOTARY_APPLE_ID --repo duggan/Subya
gh secret set NOTARY_PASSWORD --repo duggan/Subya
gh secret list --repo duggan/Subya
```

Then delete the exported .p12 (`*.p12` is in `.gitignore`, but don't leave it lying
around).

## 4. Try it

- **Dry run:** `gh workflow run release.yml --repo duggan/Subya`, then download the
  `Subya-dmg` artifact from the run. Nothing is published.
- **Test pre-release:** push a branch named `test/<anything>`.
- **Release:** bump `CFBundleShortVersionString` and `CFBundleVersion` in
  `Resources/App-Info.plist`, commit, then `git tag v0.1.0 && git push --tags`.
  A tag with a suffix, like `v0.2.0-rc1`, makes a pre-release.

The workflows run on `macos-26`, because the code needs the macOS 26 SDK. If GitHub
reports that label as unavailable, switch `runs-on` to whichever runner image ships
Xcode 26.

## Releasing from your Mac instead

`make release` does the same locally. Run `make notary-setup` once to store the
`subya` notarization profile in your keychain.
