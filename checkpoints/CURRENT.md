# CURRENT checkpoint — WeFlix Apple client

## STEP 1 — the app signs in to WeFlix (2026-10-24, Cline)

**Luther:** *"replace the 'Choose a service' (Plex / Jellyfin) first screen with a WeFlix sign-in"*. The server
half of the same step is recorded in the other repository's `checkpoints/CURRENT.md` (`APP-AUTH`, commit
`e333115`): `POST /api/app/auth/login`, `GET /api/app/me`, `POST /api/app/auth/logout` and the `app_devices`
table.

### What changed in this repository

| File | What it is |
|---|---|
| `Shared/Config/WeFlixServer.swift` | **The one place the server's address lives** — `https://weflix.me` (production), the three paths, and what this device calls itself (`deviceName`, `platform`). |
| `Shared/Features/Auth/WeFlixAccount/WeFlixAuthClient.swift` | The three calls. No token, password or header is ever logged; every refusal becomes a sentence. |
| `Shared/Features/Auth/WeFlixAccount/WeFlixDeviceTokenStore.swift` | The token, in the **Keychain** (`weflix.app.deviceToken`), never `UserDefaults`. |
| `Shared/Features/Auth/WeFlixAccount/WeFlixSessionController.swift` | Launch (`/me`), sign in, sign out — and the state the root draws. |
| `Shared/Features/Auth/WeFlixAccount/WeFlixSignInView.swift` | The screen: red icon tile, black background, bold **Sign in**, grey **Use your WeFlix account.**, username-or-email, password, full-width rounded WeFlix-red button, spinner while working, error label. |
| `Shared/Features/Auth/WeFlixAccount/WeFlixSignedInView.swift` | **Signed in as `<displayName>`** + Sign Out. The placeholder this step ends at. |
| `Shared/Features/Auth/WeFlixAccount/WeFlixAppGate.swift` | The root: spinner → sign-in → signed-in. **Where the old entry point was.** |
| `weflix-iOS/Features/ContentView.swift`, `weflix-tvOS/ContentView.swift`, `weflix-macOS/ContentView.swift` | Each keeps its old Plex/Jellyfin root as a private `PlexLibraryRootView` — compiled, commented, **unreachable**. |
| `weflixTests/Features/Auth/WeFlixAccount/*`, `weflixTests/Support/StubURLProtocol.swift` | 13 new cases: 9 offline (a stubbed transport, so every HTTP → sentence mapping is pinned) and 4 live against the beta. |
| `weflix.xcodeproj` (project + the macOS scheme) | The tvOS target keeps an explicit list of which `Shared` files it compiles, so the 7 new ones were added to it; the macOS scheme's `TestAction` gained the `WEFLIX_LIVE_TESTS` toggle. |
| `CLAUDE.md`, `docs/PROJECT.md`, `checkpoints/CURRENT.md` | New: the app had none of them. |

The Plex and Jellyfin code — `Shared/Networking/Plex`, `Shared/Providers/Jellyfin`, `AccountSetupView`,
`ServerRegistry`, `SessionManager`, the player, the downloads — is **untouched and still compiles**. `LICENSE`
and the Strimr attribution in `README.md` are untouched, as instructed.

### Decisions taken (routine, recorded rather than asked)

- **The server is `https://weflix.me` (production)**, not the beta (Luther, 2026-10-24): both deployments share
  one database, so an account works on either, but the app ships pointing at production. The client has no
  fallback between them — a client that quietly talks to another server than the one it was built for is worse
  than one that says it cannot reach it. `docs/PROJECT.md` §2 has the address in one place,
  `Shared/Config/WeFlixServer.swift`.
- **The live tests can be pointed at either deployment** (`WEFLIX_TEST_BASE_URL`), because production is deployed
  from `main`: a route that only exists on `Development` answers `404` there until Luther merges.
- **A `404` is not blamed on the network** (`.serverNeedsUpdate`, *"This WeFlix server does not have the app's
  sign-in yet. Ask Luther to update WeFlix."*). Measured today: `/api/app/*` on `weflix.me` is a `404`, so
  "check your connection" would have been a lie about a connection that works. `WeFlixAuthClientTests.a404IsNotBlamedOnTheNetwork()` pins it.
- **The root is the gate, unconditionally.** The app no longer asks `SessionManager` what to show: a device with
  an old Plex account stored would otherwise land straight in the Plex home. Everything behind the gate — the
  settings screens that still reference `AccountSetupView`, the profile flows, downloads — is unreachable with it.
- **The old root is kept as a private struct, not deleted.** Unreachable code that still compiles is a map of what
  to delete next; code that no longer compiles is nothing.
- **A launch that cannot reach WeFlix keeps the token.** A train tunnel is not a reason to make somebody type
  their password again: *"Can't reach WeFlix. Check your connection and try again."* is shown with the sign-in
  form still there. Only a real `401` forgets the token.
- **The password is dropped from memory as soon as the answer arrives**, and the fields are cleared on sign-out.
- **The Sign In button is WeFlix red in both states** — an empty form dims it (45 %) rather than draining the
  colour, so the screen reads as WeFlix before anything is typed.
- **The screen is English literals, not lookup keys.** `Localizable.xcstrings` has no entries for the new screen,
  and `String(localized:)` with a missing key prints the key itself. Localisation is a question below.
- **`WeFlixAuthClient` takes its `baseURL` and `URLSession` as parameters** so the stub tests can exist.
  Production passes the defaults (`WeFlixServer.baseURL`, `.shared`).

### A bug the live test caught

`401` meant **one** thing until the live suite ran: `.unauthenticated`, whose sentence is *"Please sign in
again."* — so a person typing a **wrong password** was told to sign in again **while looking at the sign-in
screen**. The two meanings are now separate: `login`'s `401` is *wrong details* and carries the server's own
"Invalid username or password"; `me`'s and `logout`'s `401` is a token that is over, and is what makes the app
forget it. `WeFlixAuthClientTests.theTwoMeaningsOf401AreNotTheSameThing()` pins both.

### Gate (measured, this Mac)

| Target | Command | Result |
|---|---|---|
| iOS simulator | `xcodebuild -scheme weflix -configuration Debug -destination 'id=DD8FBFD3-E3DC-4F4F-BCF2-1667EF50A8C0' build` | **BUILD SUCCEEDED**, 0 errors |
| tvOS simulator | `-scheme weflix-tvOS -destination 'id=A533891E-0975-4902-9057-0F1E30BEDF90'` | **BUILD SUCCEEDED**, 0 errors |
| macOS | `-scheme weflix-macOS -destination 'platform=macOS,arch=arm64'` | **BUILD SUCCEEDED**, 0 errors — with `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`: this machine has no Mac development profile for `me.weflix` (*"No profiles for 'me.weflix' were found"*), so it compiles and links but is not signed here |
| Tests | `xcodebuild test -scheme weflix-macOS -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO` | **exit 0, 0 failures.** The tests live on the **macOS** scheme; the `weflix` (iOS) scheme has no testables in its `TestAction` |
| Live tests | the same, with `WEFLIX_LIVE_TESTS=1`, `WEFLIX_TEST_BASE_URL=https://beta.weflix.me` and Luther's account in the scheme's test action | **exit 0 — all 15 passed**, including the whole cycle through the client: sign in → `me` → logout → `me` refused |

`WeFlixAuthClientTests` **11/11 passed** (offline, stubbed transport: both meanings of `401`, a refusal's sentence,
the rate-limit sentence, a 404 that must not blame the network, a broken body, no network, the four posted fields,
the bearer header, and the one-server rule). `WeFlixLiveAuthTests` **4/4 passed** against the real beta:
an identifier the server does not know answers *"Invalid username or password"*; a token it has never seen answers
`401`; logging out a token it never knew is answered `200`; and **`user@sample.com` signs in, `me` agrees, logout
revokes it, and the same token is refused afterwards** — the app's own `WeFlixAuthClient` doing the whole cycle.

**The live suite is opt-in** — it ships with `WEFLIX_LIVE_TESTS` and `WEFLIX_TEST_BASE_URL` `isEnabled="NO"` in the
macOS scheme, so the default run needs no network and carries no account. To run it: set `WEFLIX_LIVE_TESTS` to
`"YES"`, add `WEFLIX_TEST_IDENTIFIER`/`WEFLIX_TEST_PASSWORD` beside it (and `WEFLIX_TEST_BASE_URL` if the
deployment under test is not the one the app points at), run the tests, then take them out again. Two measured
traps: neither `TEST_RUNNER_WEFLIX_LIVE_TESTS=1` nor a shell environment variable reaches the test process, and
with the usual `shouldUseLaunchSchemeArgsEnv = "YES"` the test action ignores its own variables altogether — that
is `"NO"` now. **No credential is committed**: the pass above used the variables temporarily and they are gone
(`git grep` finds nothing).

### Simulator pass, iPhone 17 Pro (iOS 26.2 simulator)

| What | Result |
|---|---|
| The sign-in screen replaces "Choose a service" | **verified** — screenshot: red W tile, black background, *Sign in*, *Use your WeFlix account.*, both fields, the full-width WeFlix-red button |
| Wrong details show the server's sentence | **verified against the beta** by `WeFlixLiveAuthTests` (an identifier nobody owns → *"Invalid username or password"*), and by the curl pass in the other repository (a wrong password on a real account); **not** driven through the simulator's UI — see below |
| A signed-in token shows the placeholder | **verified** — screenshot: *Signed in as Lucifurr* · *WeFlix owner account* · Sign Out, with `GET /api/app/me` answering from the beta |
| Relaunch stays signed in | **verified** — terminate, install, launch; the placeholder returns from the Keychain token, twice in a row |
| Sign Out returns to Sign in | **not verified in the UI.** The tap could not be driven: this machine's Accessibility permission is not granted (*"osascript is not allowed to send keystrokes"*) and `simctl` has no input command, so the simulator's UI can be observed here but not typed into. Verified instead: the server half (logout revokes the row, and a revoked token is `401`) and the client half (`.unauthenticated` → the sign-in screen, pinned by the offline tests) |
| **Against production, today** | **verified** — screenshot: with `baseURL = https://weflix.me` the app shows the sign-in screen and *"This WeFlix server does not have the app's sign-in yet. Ask Luther to update WeFlix."*, because `/api/app/*` is a `404` there until `Development` is merged into `main`. It is exactly the state described above, and the app says so instead of blaming the network |

**A live session was already in this simulator's Keychain.** When the app was installed and launched for this
pass it came up **already signed in as Lucifurr (owner)**: a WeFlix device token was in the simulator's Keychain
under the very key this code reads (`weflix.app.deviceToken`, service `me.weflix`), and the beta answered
`GET /api/app/me` with the owner's identity. **I did not create it** — no credential was ever typed by me and
none is written down anywhere. It is either a previous build of this same flow on this simulator or a manual
sign-in by Luther. Two consequences: the placeholder and relaunch rows above are verified with a *real* server
answer, and an `app_devices` row for the owner exists on the beta that **I did not revoke** — tapping Sign Out
(or revoking the row) ends it. No token value was read, printed or recorded.

### Questions for Luther

1. **`Development` → `main`, so the app works against production.** `weflix.me` is deployed from `main`
   (`e53ce44`), which does not have `/api/app/*`: it answers `404`. The app now ships pointing at production, so
   until that merge it shows *"This WeFlix server does not have the app's sign-in yet."* Beta, which does have the
   routes, is fully verified — see the other repository's checkpoint for the curl-level pass.
2. **The `disabled` case, live.** Signing in as a switched-off account is the one branch nothing but your Admin
   → Users click can produce: approve `cline-pending-check@example.invalid` (the throwaway sign-up this pass
   made) and then disable it, or disable `user@sample.com` for a minute — either way I can close it with one
   request. Until then it is pinned structurally only.
3. **The owner's leftover token in the simulator.** The Keychain session that made this simulator come up signed
   in as *Lucifurr* was not created by me and is **not revoked** (an `app_devices` row on the server). Tapping
   Sign Out in the app ends it; the pending test account is one click to reject, too.
4. **Localisation.** The new screen is English literals; the rest of the app is translated (fr, zh-Hans) through
   `Localizable.xcstrings`. Add entries once the wording is agreed, or leave the client English-only?
5. **A temporary-password account** (`mustChangePassword`) signs in here and is not forced to change anything —
   there is no password screen in the app yet. Should the app refuse until there is one?
6. **`README.md` still describes a Plex/Jellyfin client**, and the App Store links still point at Strimr. It was
   left alone deliberately (that is where the attribution lives). Rewrite it when the Plex code is removed?
7. **The tests only run on the macOS scheme.** The `weflix` (iOS) scheme's `TestAction` lists no testables, so
   there is no one-command iOS test run. Add the same `TestableReference` to it?

## Next step

Loading the home and the libraries **from the WeFlix server**, which needs server endpoints that do not exist
yet. See `docs/PROJECT.md` §6.


