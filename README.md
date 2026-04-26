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

### ⚠️ First Launch — macOS Security Prompt

Since Shoo is not distributed through the Mac App Store, macOS will show a security warning the first time you open it.

**Option A — Right-click to Open (Easiest):**
1. Move `Shoo.app` to your **Applications** folder.
2. **Right-click** (or Control-click) `Shoo.app` and select **Open**.
3. A dialog will appear — click **Open** to confirm.

**Option B — System Settings:**
1. Try to open `Shoo.app` normally (it will be blocked).
2. Go to **System Settings** → **Privacy & Security**.
3. Scroll down to the **Security** section — you'll see *"Shoo.app was blocked"*.
4. Click **Open Anyway**.

**Option C — Terminal (if the above don't work):**
```bash
xattr -cr /Applications/Shoo.app
```
After running this command, `Shoo.app` will open normally with a double-click.

## Permissions

Shoo requires **Accessibility Access** to interact with windows and detect Mission Control state. On launch, Shoo will guide you through enabling this in:
`System Settings` → `Privacy & Security` → `Accessibility`.

## Requirements

- macOS 13.0 (Ventura) or later.

## License

MIT License. See [LICENSE](LICENSE) for details.
