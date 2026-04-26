# Shoo 🚥

Shoo is a minimalist macOS menu bar utility that gives you full control over your windows directly from **Mission Control**.

Normally, Mission Control only lets you switch windows. Shoo adds interactive "traffic light" buttons (Close and Minimize) to every window in Mission Control, allowing you to clean up your workspace without leaving the overview.

![Shoo App Icon](app_icon_placeholder.png)

## Features

- **Interactive Controls:** Adds Close and Minimize buttons to windows in Mission Control.
- **Keyboard Shortcuts:** Use standard shortcuts while hovering over windows in Mission Control:
  - `Cmd + W`: Close Window
  - `Cmd + M`: Minimize Window
  - `Cmd + Q`: Quit Application
- **Smart Onboarding:** Guided setup for Accessibility permissions.
- **Safety First:** Built-in protection against system hangs and permission revocation.

## Installation

1. **Download** the latest `Shoo.zip` from the [Releases](https://github.com/AR-1106/Shoo/releases) page.
2. **Unzip** the file.
3. **Move** `Shoo.app` to your `/Applications` folder.

### ⚠️ Security Note (Important)

Since Shoo is distributed directly and not via the App Store, macOS attaches a "quarantine" flag when you download the zip. Because you are opening an unsigned app, macOS will show a strict error: **"Shoo.app Not Opened: Apple could not verify Shoo.app is free of malware."**

Even right-clicking to open will not bypass this on modern macOS versions.

**To fix this and open Shoo:**
1. Move `Shoo.app` to your **Applications** folder.
2. Open the **Terminal** app (you can find it using Spotlight search).
3. Copy and paste the following command into Terminal and press Enter:
   ```bash
   xattr -cr /Applications/Shoo.app
   ```
4. Now, you can double-click `Shoo.app` in your Applications folder and it will open normally!

## Permissions

Shoo requires **Accessibility Access** to interact with windows and detect Mission Control state. On launch, Shoo will guide you through enabling this in:
`System Settings` → `Privacy & Security` → `Accessibility`.

## Requirements

- macOS 13.0 (Ventura) or later.

## License

MIT License. See [LICENSE](LICENSE) for details.
