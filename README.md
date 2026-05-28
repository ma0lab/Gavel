<div align="center">

# Gavel

**A macOS menu bar companion for Claude Code**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey)](https://github.com/ma0lab/Gavel/releases/latest)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-support-ff5e5b?logo=ko-fi&logoColor=white)](https://ko-fi.com/ma0lab)

[English](README.md) &nbsp;·&nbsp; [Japanese](README.ja.md)

</div>

---

Claude Code asks for permission before running tools like writing files, executing commands, or making web requests. By default it prompts you in the terminal. Gavel intercepts those requests and surfaces them in a native macOS UI — so you can approve or deny without switching focus, set up auto-allow rules for repetitive operations, and keep an eye on your rate limits from the menu bar.

## Features

**Approval UI**
- Bell animation on the menu bar icon when a request is waiting
- Native approval window with full context: tool name, input, working directory
- Two-step confirmation for deny to avoid accidental rejections
- Keyboard shortcut to open the approval window from anywhere

**Auto-allow rules**
- Define rules by tool name, file path pattern, or command pattern
- Matching requests are approved instantly without interrupting you

**Rate limits**
- 5-hour and 7-day usage displayed as progress bars in the menu popup
- Tap to switch between bar view and number view
- Reset time shown in your local timezone — e.g. `resets in 2h 14m (today 23:48)`

**Activity**
- Per-session tool call counts
- Full activity log (up to 5,000 entries)

**Voice input** *(requires [whisper.cpp](https://github.com/ggerganov/whisper.cpp))*
- Push-to-talk dictation into the frontmost app
- Filler word removal and vocabulary correction
- Voice history: re-paste recent dictations from the menu

**Quality of life**
- Auto-disables interception on screen lock, sleep, or idle
- Re-enables automatically on wake

## Requirements

- macOS 13 Ventura or later
- Apple Silicon (arm64)
- [Claude Code](https://claude.ai/code) installed

## Installation

1. Download `Gavel.dmg` from the [latest release](https://github.com/ma0lab/Gavel/releases/latest)
2. Open the DMG and drag **Gavel.app** to your Applications folder
3. Launch Gavel — it appears in your menu bar as `>_`
4. Follow the in-app setup to connect it to Claude Code

> **Gatekeeper note**: Gavel is signed with a Developer ID certificate. If macOS blocks it, go to System Settings → Privacy & Security → open anyway.

## License

MIT — see [LICENSE](LICENSE)
