# CLAUDE.md — WeFlix client agent work rules

> **Read `docs/PROJECT.md` first.** It says what this app is and what it is not.
> Then read `checkpoints/CURRENT.md` for where the work stands.
>
> Written 2026-10-24, when the app stopped being a Plex/Jellyfin client and became a **native client of the
> WeFlix server**. It mirrors the rules of the server repository (`plex-custom-frontend`) deliberately: two
> repositories, one product, one way of working.

## What this app is

A native Apple client — iPhone, iPad, Mac, Apple TV — of the **WeFlix server**. It signs in with a WeFlix
account, and every answer it draws comes from that server. It never contacts plex.tv and never talks to a Plex
or Jellyfin server directly: the server holds the Plex token, does the transcoding decisions and owns the watch
state.

## How to work

- **Read before changing.** Inspect the existing code, the platform differences and the current behaviour first.
- **Do not redesign without Luther's explicit approval.** The architecture in `docs/PROJECT.md` is approved.
- **One step at a time, and stop at the gate.** A step is finished when it builds on every target and Luther
  has been told what was measured. Do not claim `PROJECT COMPLETE` or "production ready" — this app is being
  rebuilt around a new server, and large parts of it are still the old client.
- **Never fabricate.** No invented build results, no "it works" without a command or a screenshot behind it. If
  something was not measured, write **not verified**.
- **Never print, log or commit a secret**: no token, no password, no `Authorization` header, no Plex token.
  The WeFlix device token lives in the **Keychain** and nowhere else.
- **Keep the app runnable between commits.** Every commit must build for iOS, tvOS and macOS.
- When a spec is unclear, take the literal reading, implement it, and log it under "Questions for Luther" in
  `checkpoints/CURRENT.md`.
- For routine decisions (naming, file placement, implementation details), make the sensible choice, write it in
  `checkpoints/CURRENT.md`, and carry on.

## The four targets

| Target | Notes |
|---|---|
| `weflix-iOS` | iPhone and iPad. Scheme `weflix`. |
| `weflix-tvOS` | Apple TV, plus the `weflixTopShelf` extension (Top Shelf). |
| `weflix-macOS` | Mac. Separate scheme (`weflix-macOS`) with its own window and player window. |
| `weflixTests` | Unit tests. |

**Everything that can be shared lives in `Shared/`** and is compiled into all three apps: this project uses
file-system-synchronized groups, so a new file under `Shared/` joins every target with no project edit.

## Building

- iOS simulator: `xcodebuild -project weflix.xcodeproj -scheme weflix -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
  (pass `id=<UDID>` when several runtimes define the same device name).
- tvOS simulator: `-scheme weflix-tvOS -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)'`.
- macOS: `-scheme weflix-macOS -destination 'platform=macOS'`.
- All three must finish with `** BUILD SUCCEEDED **` and **0 errors** before a commit.
- A build needs several GB. `~/Library/Developer/Xcode/DerivedData` and the ignored `build/` directory in this
  repository are the two places to reclaim space when a machine runs out.
- Configuration lives in `Config/*.xcconfig` (team, bundle identifiers, Sentry DSNs). Never commit real
  secrets there.

## Git

- Remote: `origin` = `https://github.com/heylucifurr/weflix.git` (the fork). `upstream` is the original
  Strimr project — **never push there**.
- Work happens on **`Development`**. `main` receives merges only when Luther says so.
- **Keep `LICENSE` and the original attribution untouched** (GPL-3.0, `README.md`'s "Built on Strimr" credits).
  This app is a GPL-3.0 derivative and stays one.
- No force-push, no history rewrites, no new branches without Luther's explicit approval.
- Run `git branch -a` and `git status` at the end of every session.

## Not within agent authority without Luther's explicit, per-operation approval

- Deleting the Plex/Jellyfin code (it is retired but still in the tree, on purpose).
- Changing the server the app points at (`WeFlixServer.baseURL`).
- Anything that touches his Plex server, the WeFlix server deployment, or his accounts.
- Rotating or publishing any credential.
