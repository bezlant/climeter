# cliMeter GitHub Discoverability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Maximize cliMeter's GitHub discoverability — rename to cliMeter, add topics/badges/homepage, create CI for automated release builds, set up Homebrew tap.

**Architecture:** Five independent workstreams: (1) repo rename + reference updates, (2) GitHub metadata, (3) README polish with badges, (4) GitHub Actions CI for automated `.zip` release assets, (5) Homebrew tap for `brew install --cask climeter`.

**Tech Stack:** GitHub CLI (`gh`), GitHub Actions, Xcode CLI (`xcodebuild`), Homebrew cask

---

### Task 1: Rename Repo to cliMeter

**Files:**
- Modify: `Climeter/UpdateChecker.swift:27`
- Modify: `README.md` (all `bezlant/climeter` references)
- Modify: `/Users/abezlyudniy/Projects/bezlant.github.io/dist/index.html` (portfolio Climeter link)

- [ ] **Step 1: Rename the GitHub repo**

```bash
gh repo rename cliMeter -R bezlant/climeter --yes
```

GitHub preserves a redirect from the old URL, so existing links won't break.

- [ ] **Step 2: Update UpdateChecker.swift API URL**

In `Climeter/UpdateChecker.swift:27`, change:

```swift
// Old:
let urlString = "https://api.github.com/repos/bezlant/climeter/releases/latest"
// New:
let urlString = "https://api.github.com/repos/bezlant/cliMeter/releases/latest"
```

- [ ] **Step 3: Update README references**

Replace all `bezlant/climeter` with `bezlant/cliMeter` in `README.md`:
- Line 26: releases URL
- Line 29: git clone URL

Replace the title `# Climeter` with `# cliMeter`.

Replace all other display-name occurrences of `Climeter` with `cliMeter` in prose text (lines 13, 38, 40, 54). Keep `Climeter.app` as-is since that's the binary name from Xcode.

- [ ] **Step 4: Update portfolio site link**

In `/Users/abezlyudniy/Projects/bezlant.github.io/dist/index.html`, change the hero meta link:

```html
<!-- Old: -->
<a href="https://github.com/bezlant/climeter" target="_blank">Climeter ↗</a>
<!-- New: -->
<a href="https://github.com/bezlant/cliMeter" target="_blank">cliMeter ↗</a>
```

- [ ] **Step 5: Commit and push both repos**

```bash
# climeter repo
cd /Users/abezlyudniy/Projects/climeter
git add Climeter/UpdateChecker.swift README.md
git commit -m "chore: rename display name to cliMeter"
git push

# portfolio repo
cd /Users/abezlyudniy/Projects/bezlant.github.io
git add dist/index.html
git commit -m "fix: update cliMeter link after repo rename"
git push
```

---

### Task 2: GitHub Metadata (Topics + Homepage)

No files modified — all via `gh` CLI.

- [ ] **Step 1: Add additional topics for search discoverability**

Current topics: `anthropic`, `api-usage`, `claude`, `claude-code`, `macos`, `menu-bar`, `rate-limit`, `swift`, `swiftui`

Add: `usage-monitor`, `token-usage`, `mac-app`, `native-app`, `status-bar`, `developer-tools`

```bash
gh repo edit bezlant/cliMeter --add-topic usage-monitor --add-topic token-usage --add-topic mac-app --add-topic native-app --add-topic status-bar --add-topic developer-tools
```

- [ ] **Step 2: Set homepage URL**

```bash
gh repo edit bezlant/cliMeter --homepage "https://github.com/bezlant/cliMeter#readme"
```

- [ ] **Step 3: Verify**

```bash
gh repo view bezlant/cliMeter --json repositoryTopics,homepageUrl
```

---

### Task 3: README Badges and Polish

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add social proof badges**

Replace the current badge line (line 7) with:

```markdown
[![GitHub release](https://img.shields.io/github/v/release/bezlant/cliMeter)](https://github.com/bezlant/cliMeter/releases/latest)
[![GitHub downloads](https://img.shields.io/github/downloads/bezlant/cliMeter/total)](https://github.com/bezlant/cliMeter/releases)
![macOS](https://img.shields.io/badge/macOS-14%2B-black)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
```

- [ ] **Step 2: Improve install section**

Replace the Install section with clearer instructions that include Homebrew (added in Task 5):

```markdown
## Install

### Homebrew (recommended)

\```bash
brew install bezlant/tap/climeter
\```

### Manual download

Download `Climeter.zip` from [the latest release](https://github.com/bezlant/cliMeter/releases/latest), unzip, and drag `Climeter.app` to `/Applications`.

> **Note:** The app is not notarized. On first launch, right-click → Open, or go to System Settings → Privacy & Security → Open Anyway.

### Build from source

\```bash
git clone git@github.com:bezlant/cliMeter.git
cd cliMeter
xcodebuild -scheme Climeter -configuration Release -derivedDataPath build
cp -R build/Build/Products/Release/Climeter.app /Applications/
\```
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add badges and improve install instructions"
git push
```

---

### Task 4: GitHub Actions CI for Automated Release Builds

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Create the workflow directory**

```bash
mkdir -p /Users/abezlyudniy/Projects/climeter/.github/workflows
```

- [ ] **Step 2: Create the release workflow**

Create `.github/workflows/release.yml`:

```yaml
name: Build and Release

on:
  release:
    types: [published]

permissions:
  contents: write

jobs:
  build:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.2.app/Contents/Developer

      - name: Build
        run: |
          xcodebuild -scheme Climeter \
            -configuration Release \
            -derivedDataPath build \
            CODE_SIGN_IDENTITY="-" \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGNING_ALLOWED=NO

      - name: Create zip
        run: |
          cd build/Build/Products/Release
          zip -r ../../../../Climeter.zip Climeter.app

      - name: Upload to release
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh release upload ${{ github.event.release.tag_name }} Climeter.zip --clobber
```

- [ ] **Step 3: Commit and push**

```bash
git add .github/workflows/release.yml
git commit -m "ci: add GitHub Actions workflow for automated release builds"
git push
```

- [ ] **Step 4: Test by creating a new release**

```bash
gh release create v1.0.8 --title "v1.0.8" --notes "Add automated release builds and improve discoverability" -R bezlant/cliMeter
```

- [ ] **Step 5: Verify the workflow ran and asset was uploaded**

```bash
# Wait for workflow to complete (~2-3 min)
gh run list -R bezlant/cliMeter --limit 1
# Check assets on the release
gh release view v1.0.8 -R bezlant/cliMeter --json assets
```

---

### Task 5: Homebrew Tap

**Files:**
- Create: new repo `bezlant/homebrew-tap`
- Create: `Casks/climeter.rb` in that repo

- [ ] **Step 1: Create the homebrew-tap repo**

```bash
gh repo create bezlant/homebrew-tap --public --description "Homebrew tap for bezlant's projects" --clone=false
```

- [ ] **Step 2: Clone and set up the tap structure**

```bash
cd /Users/abezlyudniy/Projects
git clone git@github.com:bezlant/homebrew-tap.git
cd homebrew-tap
mkdir -p Casks
```

- [ ] **Step 3: Get the SHA256 of the release zip**

This step must run AFTER Task 4 completes (needs the uploaded Climeter.zip).

```bash
curl -sL "https://github.com/bezlant/cliMeter/releases/download/v1.0.8/Climeter.zip" -o /tmp/Climeter.zip
shasum -a 256 /tmp/Climeter.zip | awk '{print $1}'
```

- [ ] **Step 4: Create the cask formula**

Create `Casks/climeter.rb` with the SHA256 from the previous step:

```ruby
cask "climeter" do
  version "1.0.8"
  sha256 "REPLACE_WITH_ACTUAL_SHA256"

  url "https://github.com/bezlant/cliMeter/releases/download/v#{version}/Climeter.zip"
  name "cliMeter"
  desc "macOS menu bar app for tracking Claude Code API usage"
  homepage "https://github.com/bezlant/cliMeter"

  depends_on macos: ">= :sonoma"

  app "Climeter.app"

  zap trash: [
    "~/Library/Logs/Climeter",
  ]
end
```

- [ ] **Step 5: Commit and push the tap**

```bash
cd /Users/abezlyudniy/Projects/homebrew-tap
git add Casks/climeter.rb
git commit -m "feat: add climeter cask"
git push
```

- [ ] **Step 6: Verify the tap works**

```bash
brew tap bezlant/tap
brew install --cask climeter
```

---

## Execution Order

Tasks 1-3 are independent and can run in parallel.
Task 4 must complete before Task 5 (needs the release asset for SHA256).

```
Task 1 (rename) ──┐
Task 2 (metadata) ─┼── all parallel
Task 3 (README)  ──┘
                    │
                    v
              Task 4 (CI) ── must complete first
                    │
                    v
              Task 5 (Homebrew tap)
```
