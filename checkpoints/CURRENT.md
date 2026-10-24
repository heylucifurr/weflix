## PHASE APP-GATEWAY — the reported bug: a second WeFlix user landed on the first user's profile (2026-10-24, Cline)

**Luther, after the delivery:** *"I signed in as melvie. after that the homepage says Your server did not respond.
I click profile icon i can see Lucifurr… when I check Settings accounts and server melvie. Profiles I can see
lucifurr again. This is wrong. when user signs in it should be their account."* Fixed in `1560644`.

### What was actually wrong — three defects, all in the adoption path

Read from the app's own container on the simulator, not guessed:

```text
weflix.accounts.v1  [{"plex":{"_0":{"displayName":"Melvie Ramos","id":"weflix:8"}}}]        ← this one was right
weflix.profiles.v1  [{"name":"Lucifurr","id":"local.0197d07c-…"}]                           ← the previous person
                    links: [{"profileID":"local.0197d07c-…","accountID":"plex:weflix:8"}]   ← Melvie's account,
                    activeProfileID: local.0197d07c-…                                          Lucifurr's profile
```

1. **One server identity for every WeFlix account.** `ServerIdentity` is the key `ServerRegistry` stores a
   connected server under, and every WeFlix account used `weflix-gateway`. The second sign-in therefore found the
   *first* sign-in's entry already present (`guard entries[server] == nil`), kept its link, and connected with **the
   first account's token** — which the sign-out had just revoked. That is the "Your servers did not respond": a
   revoked token reading a dead server. `WeFlixGatewayAccount.serverIdentity(for:)` is now one per account; the
   identifier the client *reports* stays `weflix-gateway`, because that is what the gateway answers in `/identity`.
2. **Adoption reused `activeProfile`.** A profile in this app is a person, and a WeFlix account is one person, so
   the profile must be the one already **linked to that account**. The rule is now
   `WeFlixGatewayAccount.profileChoice(accountID:displayName:profiles:links:)` — a pure function, so it is testable
   without a store, a registry or a network — and an account with no profile of its own gets one named after the
   person signing in.
3. **Sign-out left the account, its token and its links behind**, which is what allowed (2) to hand a dead account
   to the next person. `forgetWeFlixAccount()` now removes the account, its token, its links and any local profile it
   leaves empty, and is wired to the gate's sign-out. Adoption additionally drops any *other* WeFlix account
   (`discardOtherWeFlixAccounts`): the Keychain holds one device token, so only one WeFlix sign-in can be live — a
   second WeFlix account is a server that can never answer.

### The repair, verified live

The exact broken state was planted on the simulator (a local profile named "Lucifurr", linked to the account and
active), and the app was launched signing in as a different WeFlix user:

```text
before   profiles: [{"id":"local.stale-test","name":"Lucifurr"}]  active: local.stale-test
after    profiles: [{"id":"local.stale-test","name":"sample user"}]  accounts: [weflix:10]  ← same id, new name
         screen: Home · Libraries · Search, Continue Watching, Recently Added in Anime / in Movies
```

The profile keeps its id, so its settings survive — and a profile that a human built for several accounts, or a
Plex Home profile, is **never** renamed (a test pins that).

### Gate (measured, this Mac)

macOS suite **exit 0** (no regressions from the `SessionManager`/`ServerRegistry` edits) · iOS signed build **0
errors** · tvOS build **0 errors** · `WeFlixGatewayURLTests` **16/16** (5 new: a new account does not land on
another person's profile, a second sign-in is a no-op, the stale name is repaired, a multi-link profile is not
renamed, and two accounts have two identities).

### Still open (needs Luther's answer, not more code)

If the home *still* says "Your servers did not respond" after this fix, the reason is Melvie's **account**, not the
wiring: a pending or disabled WeFlix account is refused by the gateway (`401`), and the app's home shows its generic
wording instead of the server's own sentence. That message improvement is worth doing — with the evidence of which
refusal it is.


## PHASE APP-GATEWAY — A1–A5: the sign-in becomes a library, proved on a simulator (2026-10-24, Cline)

**Luther:** *"proceed everything. my expected delivery is when I sign in I can see movies and play it."* The
server's S1–S5 are recorded in `plex-custom-frontend/checkpoints/CURRENT.md` (S5 pushed this session, live on beta).

### State

| Task | What it is | Done |
|---|---|---|
| A1 | `WeFlixServer.gatewayPath/gatewayBaseURL/gatewayMachineIdentifier`, `ServerAccessSnapshot.speaksToGateway`, bearer header in gateway mode | `2fe9748` |
| A2 | `PlexAPIContext.selectGateway(token:accountID:displayName:)` — the Plex-shaped state built from one host, **no plex.tv call** | `2fe9748` |
| A3 | the sign-in is adopted into the app's own account/profile model and activated | `3cf4f06`, `460ed00` |
| A4 | the gate hands the screen to the platform's own library UI once the profile is `.ready` | `3cf4f06`, `460ed00` |
| A5 | no live gateway path can reach plex.tv — enforced, not merely intended | `3cf4f06` (started), this session (finished) |
| — | artwork through `/api/image` with **no credential in the URL** | `3cf4f06` |
| — | direct plays through `/api/video` and streams through `/api/transcode`, carrying the **stream ticket** | `3cf4f06` |

| File | What it is |
|---|---|
| `Shared/Features/Auth/WeFlixAccount/WeFlixGatewayAccount.swift` | **New.** The `weflix:` marker and the two things built from it: the account (`MediaAccount.plex(PlexAccount(id: "weflix:<id>"))`), the one server (`WeFlixGatewayAccount.server`), and `isGateway(_:)`, which is what `ServerRegistry` and `SessionManager` branch on before any plex.tv step. |
| `Shared/Features/Auth/WeFlixAccount/WeFlixGatewayURL.swift` | **New.** The three gateway URLs in one place: `/api/image?path=…&size=…`, `/api/video?path=…&ratingKey=…`, `/api/transcode?path=<whole Plex path>`. Plus the five-size mapping the image route accepts (a 2:3 poster is width ÷ height ≈ 0.67 — got that wrong first, and a test caught it). |
| `Shared/Features/Auth/WeFlixAccount/WeFlixStreamTicketCache.swift` | **New.** The ticket, with a synchronous read (the URL builders are sync) and an asynchronous refresh, refreshed 60 s before expiry so a play starting at T−1 s still has one. |
| `Shared/Session/SessionManager.swift` | `adoptWeFlixAccount(user:token:)`: account + link + token, then the app's own `activate → waitForFirstReady` path; `forgetWeFlixAccount()`; and A5's guards (`isWeFlixAccount`, the Home-user refresh, the switch, the server list). |
| `Shared/Session/ServerRegistry.swift` | `resolvePlex`/`connectPlex` branch on the marker **before** the two plex.tv-only steps; `resolveGateway()` adds the one server, `connectGateway()` connects it through `selectGateway()`. |
| `Shared/Features/Auth/WeFlixAccount/WeFlixAppGate.swift` | The handover: adopt on `.signedIn`, then `ready()` (the platform's own UI) once `SessionManager` is `.ready`; the app's activation screen while hydrating. |
| `Shared/Repository/Plex/ImageRepository.swift`, `MediaRepository.swift`, `PlaybackRepository.swift` | The three gateway branches. |
| `Shared/Offline/Artwork/CachedArtworkService.swift` | Artwork from `weflix.me` is loaded with a `URLSession` request carrying the bearer token — **which is why the image URL holds no credential at all**. |
| `Shared/Networking/Plex/PlexCloudNetworkClient.swift`, `PlexAPIContext.swift` | A5: `selectGateway` clears the plex.tv token, and a cloud client with no token refuses **before building a URL**. |
| `weflix-iOS/Features/ContentView.swift`, `weflix-macOS/ContentView.swift`, `weflix-tvOS/ContentView.swift` | Each passes its own library UI into the gate (`MainTabView` / `MainView`); each keeps its old Plex/Jellyfin root, unreachable. |
| `weflixTests/Features/Auth/WeFlixAccount/WeFlixGatewayURLTests.swift` | **New.** 11 cases: the marker, the five image sizes, both playback URLs, the ticket's expiry margin, the host — and A5's three (a gateway context holds no plex.tv token; a token-less cloud client refuses before sending; the one server has no connections and no token). |
| `weflix.xcodeproj` | The three new `Shared` files added to the **tvOS** target's explicit list. |

### The delivery, measured on an iPhone 17 Pro simulator against beta

The point of the whole phase was *"when I sign in I can see movies and play it"*, so it was run, not argued:

```text
launch app (SIMCTL_CHILD_WEFLIX_BASE_URL=https://beta.weflix.me)
  → signed in as the stored token's owner ("Lucifurr")
  → plist of the app's container, after the handover:
      weflix.accounts.v1  [{"plex":{"_0":{"displayName":"Lucifurr","id":"weflix:2"}}}]        ← the marker
      weflix.profiles.v1  links: [{"profileID":"local.0197…","accountID":"plex:weflix:2",
                                  "user":{"plexHome":{"uuid":"weflix:2"}}}]                   ← the link
                          activeProfileID: local.0197…                                        ← activated
  → the snapshot of the screen:
      tabs     Home · Libraries · Search                    (MainTabView — the handover happened)
      hublines Continue Watching · Recently Added in Anime · Recently Added in Movies
      items    Animals · Matchbox the Movie · VisionQuest   ("1 hr, 46 min. left")
               Theseus (S1 · E2 · 43 min. left), SPY x FAMILY, Daemons of the Shadow Realm (38)
```

And the playback URLs the app builds, fetched for real (the server side of the same evidence):

```text
GET /api/video?path=/library/parts/8973/1771860598/file.mkv&ratingKey=4292&ticket=<ticket>
      -> 200   3348196822 bytes   video/x-matroska        ← a real film, through weflix.me, ticket only
GET /api/video?…&ticket=<ticket>x                -> 401
GET /api/plex/library/sections?ticket=<ticket>    -> 401   ← a ticket is not a way into the gateway
```

**What is not yet proved by a tap:** starting a film *from the UI*. This harness exposes no tap/type tool, and the
Mac's `osascript` keystroke permission is refused, so the app's own play button could not be pressed. What is proved
instead: the library renders, the account/profile/activation state is exactly the designed one, and the media URL
the player is handed answers `200` with 3.1 GB of a real film. Playback *inside the app* is the one thing Luther
should confirm by tapping once.

### Two findings worth keeping

- **An unsigned simulator build cannot use the Keychain.** With `CODE_SIGNING_ALLOWED=NO` the app has no
  `application-identifier`, so every `SecItemAdd` fails and `WeFlixDeviceTokenStore.token()` is always `nil` — which
  looked exactly like "the stored token was refused". The run above is an **ad-hoc signed** build
  (`CODE_SIGN_IDENTITY=-`), and that is why the token was finally read. *(Both problems this session — this one and
  the `.task(id:)` handover that never fired because `adopt()` returned early on that nil token — presented as
  "stuck on the signed-in card".)*
- **A gateway account must not reach plex.tv.** It could: `UserRepository`/`ResourceRepository` build a
  `PlexCloudNetworkClient` (`https://plex.tv/api/v2`, `discover.provider.plex.tv`) from `context.authTokenCloud`,
  which `setAuthToken` had set to the **WeFlix device token** — a plex.tv request carrying the wrong credential.
  A5 closes it in two places: `selectGateway` clears the cloud token, and the cloud client refuses to build a
  request without one. Three tests pin it.

### Gate (measured, this Mac)

macOS app **0 errors**, iOS app **0 errors**, tvOS app **0 errors** (the tvOS target needed the three new files in
its list); `weflixTests/WeFlixGatewayURLTests` **11/11 pass, exit 0** (three of them A5's); the suite compiles and
runs against the same `Shared/` sources on all three platforms.

### Ledger

- **Ruling: a WeFlix account is recorded as `MediaAccount.plex` with a `weflix:` marker.** `LinkedUser` has no
  WeFlix case, and adding one would have touched every exhaustive `switch` in the session layer.
  *Cost if wrong:* the marker is a string prefix — one `isGateway()` function asks the question in one place, and
  two tests pin that a real plex.tv account is never treated as a WeFlix one.
- **Ruling: artwork carries no credential at all.** It is loaded by `CachedArtworkService` with `URLSession`, which
  *can* send the bearer header, so the URL needs no ticket — unlike playback, where `AVPlayer` cannot send one.
  *Cost if wrong:* an image request from that one loader authenticates with a header; everything else about the URL
  is unchanged.
- **Ruling: `WEFLIX_BASE_URL` (https only) and `WEFLIX_TEST_IDENTIFIER`/`_PASSWORD` exist for proving a build.**
  Beta has the routes before production does, and a simulator with no keyboard automation cannot type a sign-in.
  The credentials are read **only when there is no stored token**, and nothing shipped sets them.
  *Cost if wrong:* neither variable exists in a normal launch's environment, so neither path runs.
- **Process: never `git add -A` in this repository** (Luther works in the tree — the lesson from `d4a6370`). Every
  commit this session staged explicit paths and printed `git diff --cached --name-only` first.
- **Disk: this Mac reached 100% and builds started failing with `No space left on device`.** Only regenerable
  caches were removed — Xcode's `ModuleCache.noindex` and `SDKExplicitPrecompiledModules`, the SwiftPM cache, and
  user caches (`~/.Library/Caches/{pip,Homebrew,Google,Adobe,com.github.CopilotForXcode,com.github.GitHubClient.ShipIt,…}`)
  — never sources, and not Luther's project `DerivedData` (only its `Build/` products). ~4 GB free afterwards.



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
- **The screen is English literals, not lookup keys**, and Xcode's own extraction put them in
  `Localizable.xcstrings` during the builds (measured: `"Sign in"`, `"Sign In"`, `"Sign Out"`,
  `"Signed in as %@"`, `"Username or email"`, `"Password"`, `"Use your WeFlix account."`,
  `"WeFlix account"`, `"WeFlix owner account"`, `"Tap to dismiss"`, with auto-generated comments and **no
  translations yet**). So the wording is registered and translatable; fr and zh-Hans are the follow-up, not a
  rewrite.
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
| **Against production, today** | **verified, twice.** (a) *Before* the merge: with `baseURL = https://weflix.me` the app showed the sign-in screen and *"This WeFlix server does not have the app's sign-in yet. Ask Luther to update WeFlix."*, because `/api/app` was a `404` there. (b) *After* Luther merged `Development` → `main` (`5428f0e`) and production redeployed it: the app launched against `https://weflix.me`, called `GET /api/app/me` on production, and came up **"Signed in as Melvie Ramos · WeFlix account"** (screenshot) — a real server answer, rendered from the Keychain token |

**A live session was already in this simulator's Keychain.** When the app was installed and launched for this
pass it came up **already signed in as Lucifurr (owner)**: a WeFlix device token was in the simulator's Keychain
under the very key this code reads (`weflix.app.deviceToken`, service `me.weflix`), and the beta answered
`GET /api/app/me` with the owner's identity. **I did not create it** — no credential was ever typed by me and
none is written down anywhere. It is either a previous build of this same flow on this simulator or a manual
sign-in by Luther. Two consequences: the placeholder and relaunch rows above are verified with a *real* server
answer, and an `app_devices` row for the owner exists on the beta that **I did not revoke** — tapping Sign Out
(or revoking the row) ends it. No token value was read, printed or recorded.

### Questions for Luther

1. **Done — thank you.** `Development` → `main` landed (`origin/main` = `5428f0e`), production (`weflix.me`) now
   serves `5428f0e` and the whole cycle was re-verified against it: the app's four live tests pass with **no**
   base-URL override (so they talked to production), and the simulator came up *"Signed in as Melvie Ramos"* from
   a real `GET /api/app/me` on production. The `404` sentence stays in the code as a guard for the next time the
   two branches drift apart.
2. **The `disabled` case is now verified live** — `cline-pending-check@example.invalid`, with its correct
   password, answers **`403` · "This account has been disabled. Ask Luther to switch it back on."** on the beta
   (same database as production), and that sentence is only reachable after the password verified. Every branch
   the client can receive has now been seen from the real server.
3. **Two accounts' tokens are in this simulator's Keychain** — *Lucifurr* (earlier) and now **Melvie Ramos**,
   neither created by me: no credential of mine is stored anywhere, and the two sign-ins on that simulator were
   somebody else's (yours or an earlier session's). Both `app_devices` rows are live; Sign Out in the app ends
   the one in hand.
4. **Localisation.** The new screen's strings are extracted into `Localizable.xcstrings` with auto-generated
   comments and no translations; fr and zh-Hans are the follow-up once the wording is agreed.
5. **A temporary-password account** (`mustChangePassword`) signs in here and is not forced to change anything —
   there is no password screen in the app yet. Should the app refuse until there is one?
6. **`README.md` still describes a Plex/Jellyfin client**, and the App Store links still point at Strimr. It was
   left alone deliberately (that is where the attribution lives). Rewrite it when the Plex code is removed?
7. **The tests only run on the macOS scheme.** The `weflix` (iOS) scheme's `TestAction` lists no testables, so
   there is no one-command iOS test run. Add the same `TestableReference` to it?

## Next step — PHASE APP-GATEWAY, client tasks A1–A5 (plan approved by Luther, 2026-10-24)

Luther: *"weflix custom plex is only a skin ui. the real backend is still plex. so basically we strimr is stil
talking to plex. only via weflix.me"*. The plan is `plex-custom-frontend/phases/active/PHASE-APP-GATEWAY.md`; its
**server tasks S1–S4 are built, pushed and verified live** (see that repo's checkpoint: an app bearer token reads
`/api/plex/library/sections/all` and gets Luther's real libraries).

**Client progress in this repository**

| Task | State |
|---|---|
| **A1** — one gateway, in one place | **done** — `WeFlixServer.gatewayPath`/`gatewayBaseURL`/`gatewayMachineIdentifier`; `ServerAccessSnapshot.speaksToGateway`; `PlexServerNetworkClient` sends `Authorization: Bearer …` in gateway mode and `X-Plex-Token` otherwise. iOS + macOS + tvOS build with 0 errors. |
| **A2** — `selectGateway(token:accountID:displayName:)` | **done** — sets `baseURLServer`, `authTokenServer`, a synthetic `PlexCloudResource(name: displayName, clientIdentifier: accountID…)`, `connectionKind = .custom` and `speaksToGateway`, and bumps the generation. No plex.tv, no discovery. |
| **A3** — the WeFlix sign-in creates the Plex access | **not started.** `SessionManager.adoptWeFlixAccount(user:token:)`: build `MediaAccount.plex(PlexAccount(id: "weflix:<user.id>", displayName: user.displayName))`, activate its profile, and reach `.ready` — never `UserRepository.getUser()`/`getHomeUsers()`. |
| **A4** — the gate shows the real UI | **not started.** `WeFlixAppGate` should hand over to `MainTabView`/`MainView` once the account is adopted, and the placeholder (`WeFlixSignedInView`) goes or becomes the launching state. |
| **A5** — gateway mode never calls plex.tv | **not started.** Guard `ResourceRepository`/`AuthRepository`/`UserRepository`/`DownloadQueueRepository` so no live path reaches them, with a sweep test. |

**Ruling recorded:** this session stopped after A2 rather than opening A3, because A3+A4 rewire `SessionManager`
and the root view and need a full three-platform build and a simulator pass — work that deserves a fresh context,
and which leaves the app **exactly as shippable as it is today** (still the placeholder) if it is interrupted. The
plan's own gate is unchanged: A1–A5 together are what makes the home show movies.

**A3's wiring map, read from the code (do the next session this way, it is all measured):**

- `SessionManager` has `accountStore` (`save(account:token:)`, `setHomeToken(_:accountID:userUUID:)`), `profileStore`
  (`updatePlexHomeUsers(_:accountID:)`, `setActiveProfile(_:)`) and `registry`. `status` reaches `.ready` **only**
  through `activate(_:plexHomeToken:)` → `registry.activate(profile:links:)` → `registry.waitForFirstReady` → line
  229's `status = .ready`. So A3 must not invent a status path: adopt the account, then call `activate`.
- A gateway account **fits the existing types**, so no enum case is needed: `MediaAccount.plex(PlexAccount(id:
  "weflix:<user.id>", displayName: user.displayName))`, a `.plexHome(uuid: "weflix:<id>")` link and the profile id
  from `PlexHomeProfile.id(userUUID:)` — all existing shapes. The `weflix:` prefix is the marker that says *this
  account is the gateway*, and it is the only thing `ServerRegistry.connectPlex` needs to branch on.
- **The branch point is `ServerRegistry.connectPlex(_:)` (line ~512)**: today it does
  `plexToken(link:account:userUUID:)` (which calls plex.tv `/switch`), `context.setAuthToken(token)`,
  `context.selectServer(resource)`, then `PlexMediaServicesFactory.make(...)` and `markReady(...)`. The gateway path
  is the same minus the first three: `context.selectGateway(token: storedToken, accountID:, displayName:)`, then the
  same factory and the same `markReady`. `entry.plexResource` must be the synthetic gateway resource — set where
  `activate(profile:links:)` (line 149) builds entries.
- **A4 then removes the placeholder**: `WeFlixAppGate` hands over to `MainTabView`/`MainView` once
  `sessionManager.status == .ready`, keeping `.checking` for the spinner and `.signedOut` for the sign-in screen.

**Playback — the one thing the plan parked, and what it actually needs (measured 2026-10-24):**

The app builds its media URLs with the credential **in the query string** and hands a bare `URL` to the player:

| Where | Today |
|---|---|
| `ImageRepository.transcodeImageURL` | `{server}/photo/:/transcode?X-Plex-Token=…&url=…&width=…` |
| `MediaRepository` (line 26) | a direct-play URL with `X-Plex-Token` in the query |
| `PlaybackRepository` (line 153) | `{server}/video/:/transcode/universal/start.m3u8?…&X-Plex-Token=…` |

The gateway **refuses** a client-supplied token (`hasPlexTokenQuery`, pinned by `S2:` tests), and rightly so. So
gateway mode needs three things, in this order:

1. **Artwork and streams point at WeFlix's own routes instead of Plex paths** — `/api/image?path=…`, `/api/video?
   path=…&ratingKey=…`, `/api/transcode?path=/video/:/transcode/universal/start.m3u8?…`. All three already accept
   the app's bearer token (S3), already apply the library rule, and `/api/transcode` already rewrites HLS playlists
   to strip a token from them. This is the "see movies" half and it is small: three URL builders, gateway branch.
2. **The player's own request needs a credential it cannot carry in a header.** The player is an
   `AVPlayer`/`AetherEngine` asset built from a bare URL, and media requests carry no `Authorization` header — which
   is exactly why the app put the token in the query. The clean answer is a **short-lived stream ticket**: a new
   `POST /api/app/stream-ticket` (bearer) answering a signed, minutes-long value bound to the account and to nothing
   else, appended as `?ticket=…` to media URLs only; `lib/session-signature.ts` already has the HMAC helpers, so it
   needs no table. The long-lived device token must **not** go into a URL.
3. **The transcode *decision* call** (`PlaybackRepository`, `/video/:/transcode/universal/decision`) is a JSON read
   that S2 deliberately refused at the gateway ("playback is the next phase"). With playback in scope, add
   `decision|ping|stop` to `GATEWAY_READ_PATHS` — but **not** `start.m3u8` (which must go through `/api/transcode`,
   or its segment URLs keep a Plex token) and **not** `library/parts/<id>/<file>` (which must go through
   `/api/video`).

**Status of the delivery Luther asked for ("sign in and I can see movies and play it"): not met yet.** Today the app
still shows the placeholder: A1/A2 are in place and tested, but nothing calls `selectGateway`, and A3/A4/A5 plus the
three steps above are what put posters on the screen and a film behind the Play button.



Luther, 2026-10-24: *"weflix custom plex is only a skin ui. the real backend is still plex. so basically we strimr
is stil talking to plex. only via weflix.me"* — the client keeps its Plex plumbing, and `weflix.me` becomes the
Plex-shaped gateway in front of the real server. The plan is written and lives in the **server** repository:
`plex-custom-frontend/phases/active/PHASE-APP-GATEWAY.md` (audit, server tasks S1–S4, client tasks A1–A5, the gate,
and four open questions for Luther). **Nothing in it is implemented yet.**

In one line: **S1** teaches the request identity to accept the app's bearer token; **S2–S4** widen `/api/plex` from
the two calls a browser player needs into the set the app makes (still refusing a client-supplied token, still
applying the per-account library rule and the rate limit) and answer the `/identity` call as WeFlix; **A1–A2** point
`PlexAPIContext` at the gateway with a bearer header and no plex.tv; **A3** builds the Plex account from the WeFlix
sign-in answer instead of a PIN flow; **A4** swaps this placeholder for the real home; **A5** proves nothing on a
live path still calls plex.tv.

> **The icon regression my commit `d4a6370` swept in — fixed in `5c1ba40`, as Luther chose.** The tree had his
> **staged** app-icon work when I committed a checkpoint file: `git commit` commits the whole **index**, so it went
> in and was pushed under my message. The content was his and intact; the attribution was not. Three-target build
> then showed a real defect in it:
>
> ```text
> weflix-tvOS/Assets.xcassets:./App Icon & Top Shelf Image.brandassets/App Icon.imagestack: error:
>   The last image stack layer with content, "Back", must exactly fill the image stack.
>   Its current frame is {{-312, -392}, {1024, 1024}} while the image stack's size is {400, 240}.
> ```
>
> The square `appicon.png` (1024×1024) had replaced the correctly-shaped layers `main`'s `9a26fe6` had just
> repaired. **Luther's call was to keep the new artwork and fix the stacks**, so `5c1ba40` composes three
> stack-sized images from it (scaled to the stack width, cropped to the middle band — seamless, since the artwork's
> background is uniform and the wordmark is vertically centred) and restores main's imageset structure as PNGs:
> `logo_tvos_1280.png` (1280×768), `logo_tvos_400@1x.png` (400×240), `logo_tvos_400@2x.png` (800×480). The stray
> duplicate `appicon 1.png` files are gone. **Verified: tvOS `BUILD SUCCEEDED` with 0 actool errors (it reported
> two before); iOS and macOS unaffected, still clean; his new icon artwork is kept everywhere.** No history was
> rewritten (no force-push, per both repos' rules).
>
> **Process change from this, for every later session:** never `git add -A` / a bare `git commit` in this repo
> while anybody might be working in it — stage explicit paths and check `git diff --cached --name-only` before
> committing. My own `CLAUDE.md` says to preserve in-flight work; the index is part of that.





