# Shoo 🚥

Shoo is a minimalist macOS menu bar utility that gives you full control over your windows directly from **Mission Control**.

Normally, Mission Control only lets you switch windows. Shoo adds interactive "traffic light" buttons (Close and Minimize) to every window in Mission Control, allowing you to clean up your workspace without leaving the overview.

## Features

- **Interactive Controls:** Close and Minimize buttons on every window in Mission Control.
- **Keyboard Shortcuts** while hovering over windows in Mission Control:
  - `Cmd + W` — Close Window
  - `Cmd + M` — Minimize Window
  - `Cmd + Q` — Quit Application
- **Guided Onboarding** for Accessibility permissions.
- **Safe Permission Handling** — gracefully handles permission revocation without system hangs.

## Installation

### Quick Install (Recommended)

Run this in **Terminal** — it downloads, installs, and handles macOS security automatically:

```bash
curl -fsSL https://raw.githubusercontent.com/AR-1106/Shoo/main/install.sh | bash
```

### Manual Install

1. **Download** the latest `Shoo.dmg` from the [Releases](https://github.com/AR-1106/Shoo/releases) page.
2. **Open** the DMG and drag `Shoo.app` into your **Applications** folder.
3. **Remove quarantine** (required since the app is not notarized):
   ```bash
   xattr -cr /Applications/Shoo.app
   ```
4. Double-click `Shoo.app` to launch.

> **Why is step 3 needed?** macOS adds a quarantine flag to all files downloaded from the internet. Without an Apple Developer certificate ($99/yr), this flag causes a "cannot verify" error. The `xattr` command removes it. The quick install above handles this automatically.

## Permissions

Shoo requires **Accessibility Access** to interact with windows and detect Mission Control state. On launch, Shoo will guide you through enabling this in:
`System Settings` → `Privacy & Security` → `Accessibility`.

## Requirements

- macOS 13.0 (Ventura) or later.

## License

MIT License. See [LICENSE](LICENSE) for details.
