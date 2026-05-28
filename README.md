# Gavel

A macOS menu bar app that makes working with [Claude Code](https://claude.ai/code) more comfortable.

[日本語](README.ja.md)

[![Ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/ma0lab)

![Gavel screenshot](docs/screenshot.png)

## What it does

Claude Code asks for permission before running tools like writing files, executing commands, or making web requests. By default you answer `y` or `n` in the terminal. Gavel intercepts those requests and surfaces them in a native macOS UI — so you can approve or deny without switching focus, set up auto-allow rules for repetitive operations, and keep an eye on your rate limits from the menu bar.

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
- Per-session token usage and tool call counts
- Full activity log (up to 5,000 entries)

**Voice input** *(requires [whisper.cpp](https://github.com/ggerganov/whisper.cpp))*
- Push-to-talk dictation — speaks into the frontmost app
- Filler word removal and vocabulary correction
- Voice history: re-paste recent dictations from the menu

**Quality of life**
- Auto-disables interception on screen lock, sleep, or idle (re-enables on wake)
- Idle threshold: 60 seconds without input pauses approvals automatically

## Requirements

- macOS 13 Ventura or later
- Apple Silicon (arm64)
- [Claude Code](https://claude.ai/code) installed and set up

## Installation

1. Download `Gavel.dmg` from the [latest release](https://github.com/ma0lab/Gavel/releases/latest)
2. Open the DMG and drag **Gavel.app** to your Applications folder
3. Launch Gavel — it will appear in your menu bar as `>_`
4. Follow the in-app setup to connect it to Claude Code

> **Gatekeeper note**: Gavel is signed with a Developer ID certificate. If macOS still blocks it, go to System Settings → Privacy & Security → open anyway.

## Rate limit integration

Gavel reads rate limit data from Claude Code's [statusline API](https://docs.anthropic.com/en/docs/claude-code/settings#status-line-customization). To enable it, add this to your `~/.claude/settings.json`:

```json
{
  "statusCommand": "python3 ~/.claude/statusline.py"
}
```

Then create `~/.claude/statusline.py`:

```python
import sys, json, time

data = json.load(sys.stdin)

# Write rate limits for Gavel
rl = data.get('rate_limits', {})
five_h = rl.get('five_hour')
seven_d = rl.get('seven_day')
if five_h or seven_d:
    payload = {'updated_at': time.time()}
    if five_h:
        payload['five_hour'] = five_h
    if seven_d:
        payload['seven_day'] = seven_d
    try:
        with open('/tmp/gavel_ratelimits.json', 'w') as f:
            json.dump(payload, f)
    except Exception:
        pass

# Print your status line (customize as you like)
sessions = data.get('sessions', [])
if sessions:
    total = sum(s.get('total_cost_usd', 0) for s in sessions)
    print(f"${total:.2f} today")
```

## Building from source

```bash
git clone https://github.com/ma0lab/Gavel.git
cd Gavel
make build        # builds to dist/Gavel.app
make deploy       # builds + installs to /Applications + launches
make dmg          # builds a distributable DMG
```

Requires Xcode Command Line Tools and a valid Developer ID certificate for code signing.

## License

MIT
