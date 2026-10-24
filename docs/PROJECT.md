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
| `plex-custom-frontend` (`weflix.me` — production, deployed from `main`; Luther also runs a pre-production deployment rebuilt on every push to `Development`; both share one database) | the WeFlix **server**: accounts, sessions, the Plex connection, the playback decision engine, watch state, the web UI. Next.js, PostgreSQL. |
| **this repository** (`weflix`) | the native **client**: sign-in, and (next) home, libraries, search, player. Swift, SwiftUI. |

## 2. The one hard rule

**The app talks to the WeFlix server and to nothing else.**

- It **never contacts plex.tv** — no PIN flow, no plex.tv watchlist, no account lookup.
- It **never contacts a Plex or Jellyfin server directly** — no `PlexAPIContext`, no `JellyfinAPIContext` on a
  live path, no server discovery, no custom server addresses.
- It holds **no Plex or Jellyfin credential**. The Plex token lives on the server, inside the identity the
  server builds per request; the app only ever holds its own WeFlix bearer token.
- The server's address lives in **one place**: `Shared/Config/WeFlixServer.swift`.
- It holds **no Overseerr credential either**. Requests (Seerr) are the server's too: the app sends its WeFlix
  token to `https://weflix.me/api/app/seerr/...` and the server adds the Overseerr address, its API key and the
  identity the call acts as (`lib/app-seerr-routes.ts` on the server side).

Everything else follows from that. When the app needs something from Plex, it asks the WeFlix server; the
server holds the token, and answers. This is also why the old first screen ("Choose a service", with the Plex
and Jellyfin buttons) is gone — there is nothing left for it to choose.

**One host, and only one.** `https://weflix.me` is the app's server, and neither the pre-production deployment
Luther rebuilds on every push to `Development` nor the Plex backend behind `weflix.me` appears anywhere in this
repository — not in code, config, a plist, the docs or the tests. They are referred to by name, never by address.

## 3. Requests (done, 2026-10-25)

```
signed in ──▶ GET /api/app/me ──▶ requests.enabled ──▶ the requests screen
                                       │                    ├─ discover rails + search
                                       │                    ├─ a title ──▶ the request sheet
                                       │                    └─ My requests (+ quota)
                                       └─ false ──▶ "Requests aren't set up for your account yet. Ask Luther."
```

- **The main screen after sign-in is the requests**, not the library: a friend can browse and ask for a title
  immediately, with nothing to set up. Library browsing is a later task; `MainTabView`/`MainView` stay compiled
  and unreachable.
- The app talks to `https://weflix.me/api/app/seerr`, **bearer token only**, and the server decides the rest:
  which paths are allowed, who the call acts as, and what it is filed under. The app cannot name a user.
- **The app holds no Overseerr address, key, session or cookie.** `SeerrSessionService`, `SeerrViewModel`,
  `SeerrAuthRepository` and the auth request bodies were deleted rather than retired; the repositories take no
  base URL at all.
- Errors are plain sentences — "not set up for your account", a quota refusal, "already requested", "can't reach
  WeFlix" — and a `401` returns the app to the sign-in screen.
- Settings shows **Requests — connected via WeFlix** (or not set up) and the quota. There is no setup UI.
- Files: `Shared/Features/Auth/WeFlixAccount/WeFlixRequestsRootView.swift`, `Shared/Store/SeerrStore.swift`,
  `Shared/Networking/Seerr/**`, `Shared/Repository/Seerr/**`.

## 4. Sign-in (done, 2026-10-24)

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

## 5. What is retired, and how

The Plex and Jellyfin client is **retired, not deleted**:

- `weflix-iOS/Features/ContentView.swift`, `weflix-tvOS/ContentView.swift` and `weflix-macOS/ContentView.swift`
  each keep their old root as a private `PlexLibraryRootView`, with a comment where the old entry point was.
  Nothing in the app can reach it.
- The Plex/Jellyfin implementation (`Shared/Networking/Plex`, `Shared/Providers/Jellyfin`, `AccountSetupView`,
  `ServerRegistry`, `SessionManager`, the player, the downloads) is still in the tree and still compiles.
- It will be removed in the step that follows the server-side loading of home and libraries — keeping it
  compiled until then is deliberate: unreachable code that no longer builds tells you nothing, and code that
  builds tells you exactly what you are about to delete.

## 6. Licence and attribution

This app is **GPL-3.0** (`LICENSE`), and it is derived from **Strimr** by Wunax — its original attribution in
`README.md` stays, untouched. `upstream` in git is that project: it is read-only for us.

A modified version has to say what it came from, so the notice is now in two places and both are part of the
deliverable, not decoration: `README.md`'s **Licence** section, and **Settings → Licences** inside the app
(`Shared/Features/Settings/LicencesView.swift`, plus a `licences` category in tvOS's settings sidebar). The text
is *"WeFlix for Apple is a modified version of Strimr by wunax (https://github.com/wunax/strimr), licensed
GPL-3.0. Modified by Luther, 2026."* — the same sentence in both, so the two cannot drift apart. Neither
`LICENSE` nor any original Strimr notice is ever edited.

## 7. The next step

**Library browsing** — the home and the libraries, from the WeFlix server — is what is left. The sign-in and the
requests are done; `MainTabView` and `MainView` are still in the tree and unreachable, and putting them back on
the main path (behind the requests, or beside them) is that step. It means answering, on the server side first:

1. which endpoints the client needs (home rows, a library's contents, a title's details, search);
2. how the client authenticates them (the same bearer token, through `resolveAppToken()` — that is exactly why
   that helper exists);
3. what the server answers with (the shapes `lib/listing-rows.ts`, `lib/media-title.ts` and `lib/search-merge.ts`
   already produce for the web UI, or a slimmer one for the client).

Nothing about that is implemented. See `checkpoints/CURRENT.md` → "Questions for Luther".
