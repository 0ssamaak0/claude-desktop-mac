# Claude Desktop for macOS (Unofficial)

An **unofficial macOS desktop wrapper** for [Claude](https://claude.ai), built as a lightweight app that loads the official Claude web app.

![Desktop](docs/desktop.png)

![Chat Bar](docs/chat_bar.png)

> **Disclaimer:**
> This project is **not affiliated with, endorsed by, or sponsored by Anthropic**.
> "Claude" is a trademark of **Anthropic PBC** (or its affiliates).
> This app does not modify, scrape, or redistribute Claude content — it simply loads the official website.

---

## Features

### Floating Chat Bar
- **Quick Access Panel** - A floating window that stays on top of all apps

### Global Keyboard Shortcut
- **Toggle Chat Bar** - Set your own shortcut in Settings to instantly show/hide the chat bar from any app
- Configurable via visual keyboard recorder in preferences

### Other Features
- Native macOS desktop experience
- Lightweight WebView wrapper
- Adjustable text size (80%-120%)
- Camera and microphone support where the web app requests them
- Uses the official Claude web interface
- No tracking, no data collection
- Open source

---

## What This App Is (and Isn't)

**This app is:**
- A thin desktop wrapper around `https://claude.ai`
- A convenience app for macOS users

**This app is NOT:**
- An official Claude client
- A replacement for Anthropic’s website
- A modified or enhanced version of Claude beyond the browser shell
- An Anthropic-authored product

All functionality is provided entirely by the Claude web app itself.

---

## Login & Security Notes

- Authentication is handled by Anthropic (and any identity providers they use) on their websites
- This app does **not** intercept credentials
- No user data is stored or transmitted by this app beyond normal WebKit behavior

> Note: Login behavior for embedded browsers can change at any time.

---

## System Requirements

- **macOS 14.0 (Sonoma)** or later

---

## Installation

### Download
- Grab the latest release from the **Releases** page
  *(or build from source below)*

### Build from Source
```bash
git clone https://github.com/alexcding/gemini-desktop-mac.git
cd gemini-desktop-mac
open ClaudeDesktop.xcodeproj
# Build and run in Xcode
```

# Acknowledgments
- This project is using the same code as [Gemini Desktop](https://github.com/alexcding/gemini-desktop-mac?tab=License-1-ov-file#readme)