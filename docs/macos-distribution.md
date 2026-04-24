# macOS Distribution

This project includes a local packaging script for creating a double-clickable
macOS installer package.

## Build the installer

Run:

```sh
./scripts/build_macos_installer.sh
```

That script will:

- build the Flutter macOS app in release mode
- package the `.app` into a `.pkg` installer
- place the final installer in `dist/`

Example output:

```text
dist/ledger_app-1.0.0-macos.pkg
```

## What users do

For non-technical Mac users:

1. Download the `.pkg`
2. Double-click it
3. Follow the installer prompts
4. Open the app from `Applications`

## Important limitation

This installer is currently unsigned. On another Mac, Gatekeeper may show a
warning because it is from an unidentified developer.

For smooth public distribution, you should:

- sign the app with an Apple Developer ID
- notarize the app/package with Apple

Without that, users can still install it, but they may need to allow it in:

`System Settings -> Privacy & Security`
