# cliMeter

macOS menu bar app that tracks your Claude Code API usage in real time.

See your session and weekly limits at a glance. Know when you're running low before you hit a wall.

[![GitHub release](https://img.shields.io/github/v/release/bezlant/cliMeter)](https://github.com/bezlant/cliMeter/releases/latest)
[![GitHub downloads](https://img.shields.io/github/downloads/bezlant/cliMeter/total)](https://github.com/bezlant/cliMeter/releases)
![macOS](https://img.shields.io/badge/macOS-14%2B-black)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

![Climeter](screenshot.png)

## Why

Claude Code doesn't show how much of your rate limit you've used. You find out when you're blocked. cliMeter fixes that — a tiny progress bar in your menu bar that stays out of your way.

## Features

- **Menu bar progress bar** — color-coded (green/orange/red) so you know at a glance
- **Session + weekly tracking** — see both the 5-hour session and 7-day usage windows
- **Multi-account support** — manage multiple Claude accounts, switch between them
- **Auto-switch** — when one account hits 95% utilization, automatically activates the next
- **CLI sync** — picks up `/login` credentials automatically, no manual config needed
- **Auto-update check** — notifies you when a new version is available

## Install

### Homebrew (recommended)

```bash
brew install bezlant/tap/climeter
```

### Manual download

Download `Climeter.zip` from [the latest release](https://github.com/bezlant/cliMeter/releases/latest), unzip, and drag `Climeter.app` to `/Applications`.

> **Note:** The app is not notarized. On first launch, right-click → Open, or go to System Settings → Privacy & Security → Open Anyway.

### Build from source

```bash
git clone git@github.com:bezlant/cliMeter.git
cd cliMeter
xcodebuild -scheme Climeter -configuration Release -derivedDataPath build
cp -R build/Build/Products/Release/Climeter.app /Applications/
```

## Update

```bash
brew upgrade climeter
```

New versions are published automatically — the Homebrew cask updates on every release.

## Setup

1. Open cliMeter — it appears in your menu bar
2. Run `/login` in Claude Code
3. cliMeter detects the credentials automatically

That's it. No API keys to paste, no config files to edit.

## Security

- Credentials stored in macOS Keychain (not files)
- OAuth tokens with automatic refresh
- No data leaves your machine except API calls to `api.anthropic.com` and `console.anthropic.com`
- No analytics, no telemetry, no tracking
- Open source — read every line

## How it works

cliMeter reads the OAuth credentials that Claude Code stores in the system Keychain. It polls the Anthropic usage API every 3 minutes and displays the result. When tokens expire, it refreshes them silently. All network calls go directly to Anthropic's servers.

## Requirements

- macOS 14 (Sonoma) or later
- An active Claude Pro/Team/Enterprise subscription
- Claude Code CLI (for initial `/login`)

## License

MIT
