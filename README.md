# AI Chat for macOS

AI Chat is an unofficial macOS wrapper for the official
[Claude](https://claude.ai), [Gemini](https://gemini.google.com), and
[ChatGPT](https://chatgpt.com) web apps. It
keeps the familiar websites intact while providing one lightweight native app,
one floating Chat Bar, and one set of shortcuts.

Choose Claude, Gemini, or ChatGPT in Settings. Each provider keeps its own
persistent website session, so you can sign in to all three and switch without
signing in again.
To keep memory use low, AI Chat runs only the active provider's WebView; switching
providers opens that provider's home page.

AI Chat uses the providers' websites. It is not an API client and does not need
provider API keys.

## Screenshots

### Main window — Claude selected

![AI Chat main window with Claude selected](docs/desktop.png)

### Provider switching

![AI Chat settings showing Claude, Gemini, and ChatGPT](docs/provider_settings.png)

### Floating Chat Bar — Claude selected

![AI Chat floating Chat Bar with Claude selected](docs/chat_bar.png)

## Features

- Claude, Gemini, and ChatGPT in one native macOS app
- Provider selection shared by the main window and floating Chat Bar
- Separate persistent login data for every provider
- Consistent native commands with provider-specific website integrations
- New Chat with `Command-N`
- Private Chat with `Command-Shift-N`, mapped to Claude Incognito Chat or
  Gemini/ChatGPT Temporary Chat
- Provider-aware toolbar actions, including Claude-only features where available
- Find, back, forward, reload, sidebar, zoom, and always-on-top controls
- Customizable native toolbar
- Floating Chat Bar with global shortcuts
- Light, dark, and system themes
- Shared zoom and user-agent settings
- Launch at login, optional hidden Dock icon, and optional hidden launch window
- Uploads, downloads, camera, and microphone support when a provider requests them
- App Sandbox, hardened runtime, and outbound-network-only access

Because AI Chat integrates with live websites, a provider can change its page
structure or embedded-browser behavior at any time.

## Privacy and authentication

Each provider handles authentication on its own website. AI Chat does not
intercept your credentials, proxy conversations through an app-owned server, or
add analytics. Web content, cookies, cache, and sessions use macOS WebKit storage.

The Reset Website Data action clears the stored website data for all providers.

## Requirements

- macOS 26.0 or later
- Apple silicon Mac

## Install

Download a release from this repository's **Releases** page, or build the app
from source.

```bash
git clone https://github.com/0ssamaak0/ai-chat-mac.git
cd ai-chat-mac
open AIChat.xcodeproj
```

Select the `AIChat` scheme in Xcode and run it on **My Mac**. For an unsigned
command-line release build and DMG instructions, see
[build_instructions.md](build_instructions.md).

Run the provider architecture tests from the command line:

```bash
xcodebuild test \
  -project AIChat.xcodeproj \
  -scheme AIChat \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:AIChatTests \
  CODE_SIGNING_ALLOWED=NO
```

The project targets macOS 26 and arm64. Its only Swift package dependency is
[KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts), pinned to
version 3.0.1.

## Unofficial app and trademarks

AI Chat is not affiliated with, endorsed by, or sponsored by Anthropic, Google,
or OpenAI. Claude is a trademark of Anthropic PBC. Gemini and Google are
trademarks of Google LLC. ChatGPT and OpenAI are trademarks of OpenAI. All
provider names, marks, website content, and services belong to their respective
owners.

## License and attribution

This repository is distributed under the
[Creative Commons Attribution-NonCommercial 4.0 International License](LICENSE).
The license permits sharing and adaptation with attribution for noncommercial
purposes; it does not permit commercial use.

AI Chat is an adapted work based on
[Gemini Desktop](https://github.com/alexcding/gemini-desktop-mac) by alexcding.
The original copyright and license notice is preserved in [LICENSE](LICENSE).
Changes were made to add Claude and ChatGPT support and combine all three web
apps into this provider-switching app.
