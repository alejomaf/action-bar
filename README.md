<div align="center">

# Action Bar

**Your GitHub Actions, in your menu bar.**

A lightweight, native macOS menu bar app that gives developers a live, at-a-glance overview of GitHub Actions activity across all the repositories they care about — without ever opening the browser.

[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Status](https://img.shields.io/badge/status-early%20development-yellow)](#roadmap)

</div>

---

## Why Action Bar?

If you push code many times a day across several repositories, you probably end up with a tab permanently open on `github.com/.../actions`, refreshing it constantly to see whether CI is green, whether a deploy queued, or whether something just broke on `main`.

**Action Bar replaces that tab.** It lives quietly in your macOS menu bar and tells you, at a glance:

- How many workflows are running or queued right now
- Which repositories have activity
- What workflow is running, on which branch, by whom, for how long
- Whether anything failed recently — and lets you jump straight to the run page or the logs

It is **intentionally not** a full GitHub client. No issues, no PRs, no code browsing. One job, done well.

---

## Features

### Available now (early development)

- Native SwiftUI menu bar app built on `MenuBarExtra`
- Repository-grouped workflow run list with status, branch, actor, and elapsed time
- Smart status icon that reflects aggregate activity (active count, recent failure)
- Click a run to open it in your browser, ⌘-click to copy its URL, context menu for logs
- Local repository registry persisted via `UserDefaults`
- Settings window with add/remove repositories and runtime info
- Currently runs on **preview data** while live syncing is being wired up

### Planned for v0.1 (MVP)

- GitHub OAuth Device Flow authentication (no backend required) + Personal Access Token fallback
- Token storage in the macOS Keychain
- Live workflow runs via the GitHub GraphQL API
- Adaptive polling: 15s while runs are active, 60s when idle, paused on sleep
- Native notifications when watched workflows fail
- Launch at login (`SMAppService`)
- Empty / error / rate-limited states

See the [Roadmap](#roadmap) for what comes after v0.1.

---

## Screenshots

> Screenshots will be added once the live sync slice lands.
> The current build runs on preview data and looks like the dropdown described in the [UX section](#ux-overview).

---

## Requirements

- **macOS 14 Sonoma** or later
- **Swift 6 / Xcode 16** to build from source

The runtime requirements are intentionally modern so the codebase can rely on SwiftUI's `MenuBarExtra(.window)`, the `Observation` framework, `SMAppService`, and Swift 6 strict concurrency.

---

## Install

> Pre-built releases are not yet published. Until v0.1 ships, you can still build a local `.app` bundle and install it into `~/Applications`.

Once v0.1 is released:

- **GitHub Releases** — download the latest notarized `.dmg`
- **Homebrew Cask** *(planned for v0.4)* — `brew install --cask action-bar`

### Local install right now

```bash
make app
make install
```

This produces `dist/ActionBar.app` and installs a local copy to `~/Applications/ActionBar.app`.

---

## Build from source

Action Bar is currently a Swift Package, which means you can build, test, and run it without an Xcode project.

```bash
git clone https://github.com/alejomaf/action-bar.git
cd action-bar
swift build
swift run ActionBar
```

To run the test suite:

```bash
swift test
```

To build a local app bundle without installing it:

```bash
./scripts/build-app.sh
```

If you prefer Xcode:

```bash
open Package.swift
```

This opens the package directly in Xcode, where you can run the `ActionBar` scheme.

---

## UX overview

Action Bar lives in the macOS menu bar. Clicking the icon opens a compact panel:

```
┌──────────────────────────────────────────────┐
│ Action Bar                  [⚙︎]   [↻]        │
│ 3 active workflows                            │
├──────────────────────────────────────────────┤
│ owner/repo-one                                │
│   ⚡  CI       · main · 1m 23s · alex          │
│   ✓  Deploy   · main · 2m ago                 │
│                                                │
│ owner/repo-two                                │
│   ✗  Tests    · feature/x · 5m ago            │
├──────────────────────────────────────────────┤
│ Updated 12s ago         Rate 4823/5000        │
└──────────────────────────────────────────────┘
```

The **menu bar icon** itself reflects aggregate state:

| State                           | Icon                        | Badge        |
| ------------------------------- | --------------------------- | ------------ |
| Idle, no recent activity        | `bolt.circle`               | —            |
| One or more runs in progress    | `bolt.circle.fill`          | active count |
| Recent failure (last 30 min)    | `exclamationmark.circle.fill` | red accent  |
| Refreshing                      | (above) + small spinner     | —            |

The **Settings window** is a separate scene reachable from the panel and provides repository management, refresh information, and account state.

---

## Architecture

Action Bar is built around a few simple primitives:

- **`ActionBarApp`** — the SwiftUI `App` entry point. Hosts the `MenuBarExtra` scene and the `Settings` scene. Sets activation policy to `.accessory` so no Dock icon appears.
- **`AppStore`** — an `@Observable`, `@MainActor`-isolated store that holds repositories, run groups, refresh state, errors, and rate-limit info. Owned by the app, injected into views.
- **`GitHubClient`** — an `actor` that talks to GitHub. Today it returns preview snapshots; it will grow GraphQL + REST methods backed by `URLSession` and ETag caching.
- **`RunPoller`** — an `actor` responsible for refresh cadence and (eventually) backoff/scheduling.
- **`RepositoryRegistry`** — persists the user's tracked repositories via `UserDefaults`.
- **`MenuBarPanel` / `SettingsView`** — pure SwiftUI views that read from `AppStore`.

### Project structure

```
action-bar/
├── Package.swift
├── Sources/
│   └── ActionBar/
│       ├── App/                     # @main, AppDelegate, AppStore
│       ├── Core/
│       │   ├── GitHub/              # GitHubClient + (future) GraphQL/REST
│       │   ├── Models/              # Repository, WorkflowRun, ActivitySummary
│       │   ├── Polling/             # RunPoller actor
│       │   └── Storage/             # RepositoryRegistry, (future) KeychainStore
│       └── Features/
│           ├── MenuBar/             # MenuBarPanel, StatusBarLabel
│           └── Settings/            # SettingsView
└── Tests/
    └── ActionBarTests/              # swift-testing target
```

Folders are organized **by feature** (not by layer), with shared infrastructure in `Core/`.

### Tech choices, briefly

| Choice                  | Rationale                                                              |
| ----------------------- | ---------------------------------------------------------------------- |
| Swift 6 + strict concurrency | Future-proof; cheaper to start strict than retrofit later         |
| SwiftUI `MenuBarExtra(.window)` | Native, modern, custom panel UI without AppKit boilerplate    |
| macOS 14+ minimum       | Enables `@Observable`, modern `MenuBarExtra`, `SMAppService`           |
| OAuth Device Flow       | No backend required, ideal for an OSS desktop app                      |
| GraphQL primary, REST secondary | One batched query for the hot path = minimal rate-limit cost  |
| Zero third-party dependencies (MVP) | Trivially auditable, friendly to contributors             |
| `UserDefaults` + Keychain | Right-sized persistence; nothing heavier needed                      |

---

## GitHub API strategy

- **GraphQL** is used for the hot path (the dropdown). A single batched query fetches the most recent N workflow runs across every tracked repository, returning only the fields the UI needs. One rate-limit charge per refresh, regardless of how many repos you track.
- **REST** is used for endpoints GraphQL doesn't cover well: repository search/autocomplete in Settings, run/job detail (post-MVP), and the rate-limit endpoint shown in the footer.
- **Caching** uses `URLSession`'s default cache plus `If-None-Match` ETags. A `304 Not Modified` is treated as "no change" — no re-render, no churn.
- **Adaptive polling** boosts the refresh cadence to 15s when at least one run is active and falls back to 60s when idle. Below ~100 remaining rate-limit points, polling backs off automatically.

---

## Authentication & security

- **Primary auth:** GitHub OAuth Device Flow. You click *Sign in*, see a short user code, and authorize on `github.com/login/device`. The app polls for a token. No backend, no client secret.
- **Fallback:** Personal Access Token (fine-grained, read-only) for power users and GitHub Enterprise.
- **Token storage:** macOS **Keychain** (`kSecClassGenericPassword`, `kSecAttrAccessibleAfterFirstUnlock`).
- **Required scopes (MVP, read-only):** `repo` (or `public_repo` if you only track public repos). Write scopes like `workflow` are **not** requested.
- **Network endpoints:** only `api.github.com` (and `github.com` for the device-flow URL the user opens).
- **Sandboxing:** App Sandbox enabled with `com.apple.security.network.client` only.
- **Distribution:** Hardened Runtime, Developer ID code-signed, notarized via `notarytool` in CI.
- **Telemetry:** none. No analytics, no crash reporting, no remote configuration.

### OAuth setup during development

Until the project ships with a production GitHub OAuth App registration, local builds expect **your own GitHub OAuth Client ID**:

1. Create a GitHub OAuth App.
2. Copy its **Client ID**.
3. Paste it into *Settings → Account* inside Action Bar.

You can also provide it through the environment when launching from source:

```bash
export ACTION_BAR_GITHUB_CLIENT_ID=your_client_id
swift run ActionBar
```

No client secret is stored or needed for Device Flow.

If you find a security issue, please follow [`SECURITY.md`](SECURITY.md) (coming soon) — do not open a public issue.

---

## Configuration

For now, all configuration lives inside the app:

- **Tracked repositories** — managed in *Settings → Repositories* (`owner/name` format).
- **Refresh cadence** — automatic and adaptive (15s active / 60s idle).
- **Account** — once auth lands, sign-in/out happens in *Settings → Account*.

Power users will be able to override defaults via *Settings → General* in v0.1.

---

## Roadmap

| Version | Theme              | Highlights                                                                                       |
| ------- | ------------------ | ------------------------------------------------------------------------------------------------ |
| **v0.1**  | **MVP**            | OAuth Device Flow, Keychain, live GraphQL sync, adaptive polling, notifications, launch at login |
| v0.2    | Quality of life    | Per-repo branch/workflow filters, re-run failed runs, pinned runs, Sparkle 2 auto-updates        |
| v0.3    | Power users        | Multiple GitHub accounts, GitHub Enterprise Server, job-level expansion, custom notification rules |
| v0.4    | Polish & ecosystem | Desktop widget, Focus filter integration, localization, Homebrew Cask                            |
| v1.0    | Stability          | Full test coverage, opt-in privacy-respecting telemetry, signed/notarized release pipeline       |

**Explicitly out of scope (forever):** issues/PRs/code browsing, multi-CI providers, team-wide dashboards.

---

## Contributing

Action Bar is an early-stage open-source project and contributions are very welcome — especially around UX polish, accessibility, and live API plumbing.

Quick start:

1. Fork and clone the repo.
2. `swift build && swift test` should pass.
3. Open an issue first for anything non-trivial, so we can align on direction.
4. Keep PRs focused and include screenshots when touching UI.

A more detailed `CONTRIBUTING.md` will land alongside v0.1.

### Coding conventions

- Swift 6, strict concurrency.
- Folders organized by feature, not by layer.
- One primary type per file, file name matches type name.
- Prefer `@Observable` over `ObservableObject`.
- Prefer `actor` for anything that owns mutable shared state across async boundaries.
- No third-party dependencies without strong justification.

---

## FAQ

**Is this an official GitHub product?**
No. Action Bar is an independent open-source project and is not affiliated with or endorsed by GitHub.

**Does it work with private repositories?**
Yes — once authenticated with appropriate scopes, Action Bar can show workflow runs from any repository you have access to.

**Does it support GitLab / Bitbucket / CircleCI / Jenkins?**
No, and there are no plans to. Action Bar is GitHub Actions-only by design.

**Why macOS 14 and not earlier?**
Because building on `MenuBarExtra(.window)`, `@Observable`, and `SMAppService` removes a meaningful amount of glue code and bug surface. Supporting older macOS versions would meaningfully complicate the project for a small audience gain.

**Will there be a Windows or Linux version?**
No. Action Bar is intentionally a native macOS app.

**Does it cost anything?**
No. It is free and open source under the MIT license.

**Does it send my data anywhere?**
No telemetry, no analytics, no third-party services. The app talks only to GitHub's API on your behalf, using your token.

---

## License

Action Bar is released under the [MIT License](LICENSE).
