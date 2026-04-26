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

Since Shoo is distributed directly and not via the App Store, macOS will show a security warning: *"Shoo can't be opened because Apple cannot check it for malicious software."*

**To open Shoo for the first time:**
1. **Right-click** (or Control-click) `Shoo.app` in your Applications folder.
2. Select **Open** from the context menu.
3. A different dialog will appear with an **Open** button. Click it.

## Permissions

Shoo requires **Accessibility Access** to interact with windows and detect Mission Control state. On launch, Shoo will guide you through enabling this in:
`System Settings` → `Privacy & Security` → `Accessibility`.

## Requirements

- macOS 13.0 (Ventura) or later.

## License

MIT License. See [LICENSE](LICENSE) for details.
