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

**And it holds no Overseerr credential either.** Requests go *app → WeFlix → Overseerr*:
`https://weflix.me/api/app/seerr/...` with the device's bearer token, and the server adds the Overseerr address,
its API key and the identity the call acts as. The app cannot name a user, has no Overseerr address to configure
and has no Seerr sign-in of its own — `SeerrNetworkClient`, `SeerrStore` and `Shared/Repository/Seerr/**` are the
whole of it.

**One host, named once.** `https://weflix.me` lives in `Shared/Config/WeFlixServer.swift` and nowhere else. The
pre-production deployment Luther rebuilds on every push to `Development`, and the Plex backend behind
`weflix.me`, must **never** appear in this repository — not in code, config, a plist, the docs or the tests.
Refer to them by name, never by address. (Measured: `grep -rn 'beta\.weflix' .` returns nothing.)

## How to work

- **Read before changing.** Inspect the existing code, the platform differences and the current behaviour first.
- **Do not redesign without Luther's explicit approval.** The architecture in `docs/PROJECT.md` is approved.
- **One step at a time, and stop at the gate.** A step is finished when it builds on every target and Luther
  has been told what was measured. Do not claim `PROJECT COMPLETE` or "production ready" — this app is being
  rebuilt around a new server, and large parts of it are still the old client.
- **Never fabricate.** No invented build results, no "it works" without a command or a screenshot behind it. If
  something was not measured, write **not verified**.
- **Never print, log or commit a secret**: no token, no password, no `Authorization` header, no Plex token, no
  Overseerr API key. The WeFlix device token lives in the **Keychain** and nowhere else; test credentials come
  only from the server repository's `.env.test.local` and are never echoed.
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

**Everything that can be shared lives in `Shared/`** and is compiled into all three apps. **A new file under
`Shared/` needs one project edit**: the `weflix-tvOS` target's `Shared` group is an *allow-list*
(`PBXFileSystemSynchronizedBuildFileExceptionSet`, `E9C449F82EF322DE00D2895B` in `weflix.xcodeproj/project.pbxproj`),
so a file that is not named there compiles on iOS and macOS and is missing on tvOS. Add it in sorted order, and
remove the entry when you delete the file. (iOS and macOS take all of `Shared/` by default.)

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
