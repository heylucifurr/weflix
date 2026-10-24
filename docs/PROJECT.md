# PROJECT.md — the WeFlix Apple client

> **Read this file first.** It is the purpose, the architecture and the boundary of this repository.
> Written 2026-10-24, when the app became a **native client of the WeFlix server**.
>
> **Status:** the first step of the rebuild is done — the app signs in to WeFlix and shows who is signed in.
> The home, the libraries, search and the player the app was born with read **Plex and Jellyfin directly**, and
> are therefore **not usable any more**: nothing in the UI reaches them. Loading them from the WeFlix server is
> the next step.

## 1. What this app is

WeFlix is a streaming client for Apple platforms (iPhone, iPad, Mac, Apple TV). It is **the client half of a
two-repository product**:

| Repository | What it is |
|---|---|
| `plex-custom-frontend` (`weflix.me` — production, deployed from `main`; beta: `beta.weflix.me`, deployed on every push to `Development`; both share one database) | the WeFlix **server**: accounts, sessions, the Plex connection, the playback decision engine, watch state, the web UI. Next.js, PostgreSQL. |
| **this repository** (`weflix`) | the native **client**: sign-in, and (next) home, libraries, search, player. Swift, SwiftUI. |

## 2. The one hard rule

**The app talks to the WeFlix server and to nothing else.**

- It **never contacts plex.tv** — no PIN flow, no plex.tv watchlist, no account lookup.
- It **never contacts a Plex or Jellyfin server directly** — no `PlexAPIContext`, no `JellyfinAPIContext` on a
  live path, no server discovery, no custom server addresses.
- It holds **no Plex or Jellyfin credential**. The Plex token lives on the server, inside the identity the
  server builds per request; the app only ever holds its own WeFlix bearer token.
- The server's address lives in **one place**: `Shared/Config/WeFlixServer.swift`.

Everything else follows from that. When the app needs something from Plex, it asks the WeFlix server; the
server holds the token, and answers. This is also why the old first screen ("Choose a service", with the Plex
and Jellyfin buttons) is gone — there is nothing left for it to choose.

## 3. Sign-in (done, 2026-10-24)

```
app launch
  ├─ token in the Keychain?  ── no ──▶  Sign in screen
  └─ yes ──▶ GET /api/app/me ──▶ 200  ──▶  "Signed in as <displayName>" + Sign Out
                              └─ 401  ──▶  token forgotten ──▶ Sign in screen
```

- `POST /api/app/auth/login` — `{ identifier, password, deviceName, platform }` → a token (returned once)
  and `{ id, displayName, isOwner }`. The account's **email or its display name** both work.
- The token goes into the **Keychain** (`WeFlixDeviceTokenStore`), never `UserDefaults`, and is never logged.
- `POST /api/app/auth/logout` revokes it **on the server**; the app forgets it locally whatever the network did.
- The account, the password hashing (argon2id), the lockout ladder, the rate limiting and the pending/disabled
  rules all live on the server. The client shows the sentence it is given.

Files: `Shared/Features/Auth/WeFlixAccount/**`, `Shared/Config/WeFlixServer.swift`.

## 4. What is retired, and how

The Plex and Jellyfin client is **retired, not deleted**:

- `weflix-iOS/Features/ContentView.swift`, `weflix-tvOS/ContentView.swift` and `weflix-macOS/ContentView.swift`
  each keep their old root as a private `PlexLibraryRootView`, with a comment where the old entry point was.
  Nothing in the app can reach it.
- The Plex/Jellyfin implementation (`Shared/Networking/Plex`, `Shared/Providers/Jellyfin`, `AccountSetupView`,
  `ServerRegistry`, `SessionManager`, the player, the downloads) is still in the tree and still compiles.
- It will be removed in the step that follows the server-side loading of home and libraries — keeping it
  compiled until then is deliberate: unreachable code that no longer builds tells you nothing, and code that
  builds tells you exactly what you are about to delete.

## 5. Licence and attribution

This app is **GPL-3.0** (`LICENSE`), and it is derived from **Strimr** by Wunax — its original attribution in
`README.md` stays, untouched. `upstream` in git is that project: it is read-only for us.

## 6. The next step

Loading the home and the libraries from the WeFlix server, which means answering, on the server side first:

1. which endpoints the client needs (home rows, a library's contents, a title's details, search);
2. how the client authenticates them (the same bearer token, through `resolveAppToken()` — that is exactly why
   that helper exists);
3. what the server answers with (the shapes `lib/listing-rows.ts`, `lib/media-title.ts` and `lib/search-merge.ts`
   already produce for the web UI, or a slimmer one for the client).

Nothing about that is implemented. See `checkpoints/CURRENT.md` → "Questions for Luther".
