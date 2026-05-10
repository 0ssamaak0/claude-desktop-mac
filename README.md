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

### Customizable Toolbar (Tahoe Liquid Glass)
- Real `NSToolbar` with **drag-and-drop reordering** and per-window autosaved layout
- Toolbar items render as **floating glass pills** over the WebView (edge-to-edge content)
- Built-in items:
  - **Find** — Finder-style collapsible search field; `Cmd+F` focuses it and drives `WKWebView.find` as you type
  - **Sidebar** — toggles Claude.ai's own sidebar (injects `Cmd+.`)
  - **Projects** — jumps to `claude.ai/projects`
  - **New Chat** / **New Project** — one-click creation
  - **Claude Settings (gear)** — opens Claude.ai's settings (injects `Shift+Cmd+,`)
  - **Back / Forward**, **Always on Top**, **Chat Bar** toggle
- Right-click the toolbar to customize which items are visible

### Floating Chat Bar
- A floating panel that stays on top of all apps for quick prompts
- **Position on Screen** — bottom-left / bottom-center / bottom-right, or remember last location
- **Quick Ask with Selection** — global shortcut that opens the chat bar and pastes the selected text from the frontmost app (requires Accessibility permission)
- Separate global shortcut to **toggle the chat bar** from anywhere

### Performance
- **Idle WebView suspension** — when the window is hidden, the `WKWebView` is fully torn down so the WebContent process releases memory; rebuilt on resume
- Conversation-state polling replaced with a `MutationObserver` push (no 1 Hz wake-ups)
- Release builds use `-Osize` + symbol stripping; dSYM still emitted

### Other Features
- Native macOS desktop experience
- Lightweight WebView wrapper
- Adjustable text size (60%–140%) and page magnification
- Camera and microphone support where the web app requests them
- App theme: Light / Dark / System
- User-agent picker: Safari / Chrome / Custom
- Launch at login, hide dock icon, hide window at launch
- Reset website data (cookies, cache, sessions)
- No tracking, no data collection
- Open source

---

## What This App Is (and Isn't)

**This app is:**
- A thin desktop wrapper around `https://claude.ai`
- A convenience app for macOS users

**This app is NOT:**
- An official Claude client
- A replacement for Anthropic's website
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

- **macOS 26.0 (Tahoe)** or later
  *(the Liquid Glass toolbar and current performance work are Tahoe-only; older macOS versions are no longer supported as of 0.3)*

---

## Installation

### Download
- Grab the latest release from the **Releases** page
  *(or build from source below)*

### Build from Source
```bash
git clone https://github.com/0ssamaak0/claude-desktop-mac.git
cd claude-desktop-mac
open ClaudeDesktop.xcodeproj
# Build and run in Xcode
```

# Acknowledgments
- This project is using the same code as [Gemini Desktop](https://github.com/alexcding/gemini-desktop-mac?tab=License-1-ov-file#readme)
