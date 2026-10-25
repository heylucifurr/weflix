## FIX — the library filters are chips in the row, not a pill that uncollapses (2026-10-25, Cline)

**Luther, looking at the row the commit above produced:** *"no need to uncollapse the filer. i want it all visible in
one row like i explained previously."*

Combining the two rows was not the whole ask: `Filter` was still a **pill**, and tapping it *uncollapsed* the
library's real filters (`Genre`, `Decade`, …) as a second line. The filters are now **chips in the row itself**, in
the slot where that pill was — nothing to open, nothing below.

- The pill block in `LibraryBrowsePillsRow.serverPills` (`Shared/Features/Library/LibraryBrowseControlsView.swift`)
  is replaced by the Plex filter chips (and the Jellyfin ones, for a Jellyfin server) — the same `ForEach` the
  panel used to draw.
- `LibraryBrowseControlsView`'s `.filters` panel renders `EmptyView()` and its `filterOptions`/`filterLabel` are
  gone; `filterLabel` now lives in the pills row, where the chips are.
- **Unchanged on purpose:** a filter with **values** still opens its chooser as a **sheet** (`toggleFilter`), and a
  boolean one (`Unwatched`, `In progress`) still toggles on the spot. The **Type** (`Movies`) and **Sort** pills
  keep their one-tap option rows — he named the filter, and a sort's ten-odd chips inline would be a much longer
  row. **If "all visible" meant those too, say so and it is the same change twice.**

**Gate:** iOS · tvOS · macOS **BUILD SUCCEEDED**, 0 errors; `xcodebuild test` **TEST SUCCEEDED — 425 passed**.
**Not verified:** no eye has seen the row.


## FEATURE — one filter row on the library screen, and the app's plays on the dashboard (2026-10-25, Cline)

**Luther, two asks in one message.**

### 1. *"1 combined filter — Recommended Movies Filter Sort and thumb"*

The library screen had two rows: the tab chips (`Recommended · Browse · Collections · Playlists`) and, inside
Browse, a second row of filter pills. He chose the exact result:

> *"Drop Browse entirely: one row reads `Recommended | Movies | Filter | Sort | 🔳`, and tapping any of
> Movies/Filter/Sort puts you in the grid; Recommended returns to the rails."*

| File | What |
|---|---|
| `Shared/Features/Library/LibraryDetailTabPicker.swift` | Now generic over a **trailing** view, rendered after the chips **in the same `HStack` and the same `ScrollView`** — that is what makes one row. An `EmptyView` convenience init keeps the old call shape. |
| `Shared/Features/Library/LibraryBrowseControlsView.swift` | The pills were extracted into `LibraryBrowsePillsRow` (same file, so no project edit), which renders them with no scroll view of its own; `showsTopRow: Bool` lets a caller that owns the row keep the pills out of a second one. |
| `Shared/Features/Library/LibraryBrowseControlsViewModel.swift` | `onUserInteraction` — called when a pill is used (panel, type, reset). The detail screen uses it to move into the grid, which is what the removed Browse chip did. |
| `weflix-iOS` / `weflix-macOS` `Features/Library/Detail/LibraryDetailView.swift` | Own the browse view model (`@State`, created on first appearance, because its dependencies are environment values), render the single row, and pass `showsControlsRow: false` down so the pills are not drawn twice. `tabChips` is `[.recommended]`, or `[]` for a collection/playlist library (no rails to recommend). |
| `weflix-iOS` / `weflix-macOS` `…/LibraryBrowseView.swift` | `showsControlsRow` (default `true`) → `showsTopRow`. |
| `weflix-tvOS/…/LibraryDetailView.swift` | **Only** Collections and Playlists were removed. Browse stays: tvOS's switcher is a focus **sidebar** beside the content, not a chip row above it, so the pills cannot sit in it and it is tvOS's only way into the grid. **Not done on tvOS: the one-row merge** — that is a different layout, and it is recorded here rather than half-built. |

**Collections and Playlists are not orphaned** — the Libraries screen lists them (`LibraryViewModel`) and the home
rails carry them; only their chips on this screen are gone, as asked.

### 2. *"anyone uses app is not tracking"* — the dashboard

Read from the server, not guessed. Admin → Now Playing has **two** halves: Plex's `/status/sessions`, and WeFlix's
own `playback_sessions` rows, which **`POST /api/playback/heartbeat`** writes — the web player's own report. This
app never called it: it reported to Plex's `/:/timeline`, which **the server stopped writing** (*"nothing at all is
written to `/:/timeline` or `/:/scrobble`"*) *and* which the gateway refuses. So an app playback was invisible on
the dashboard **and saved no progress at all** — the `watch_progress` row that resume and the watched mark come
from is written by that same heartbeat.

| File | What |
|---|---|
| `Shared/Features/Auth/WeFlixAccount/WeFlixPlaybackHeartbeat.swift` | **New.** `POST api/playback/heartbeat` with the device bearer token: rating key, **milliseconds**, state, `playMode`, the live transcode's key, and the item's GUID when there is one. `body(for:)` is pure so a test pins every field. A refusal is thrown with the server's own sentence (`409` = the stream limit). **Named in the tvOS `Shared` allow-list**; verified by `WeFlixPlaybackHeartbeat.o` in the tvOS build's intermediates. |
| `Shared/Config/WeFlixServer.swift` | `playbackHeartbeatPath`. |
| `Shared/Providers/Plex/PlexMediaServices.swift` | `report(plan:position:state:)` — the **one** funnel behind `reportStarted`/`reportProgress`/`reportStopped` — sends the heartbeat on a gateway server and keeps `/:/timeline` for a server with its own Plex token. Nothing else about playback changed. |
| `weflixTests/Features/Auth/WeFlixAccount/WeFlixPlaybackHeartbeatTests.swift` | **New, 5 tests**: milliseconds not seconds, `direct` carries no transcode key, a transcode carries its key, `stopped` closes, an empty GUID/key is omitted, and the three states are the route's own words. |

### Gate (measured, this Mac)

| Target | Result |
|---|---|
| iOS / tvOS / macOS | **BUILD SUCCEEDED**, 0 errors each |
| Tests | **TEST SUCCEEDED — 425 cases passed, 0 failures** (420 before, +5 here) |

The three builds use `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` (this machine's SwiftPM-bundle Finder
detritus, as recorded above).

### Not verified

- **Neither change has been seen by an eye or a tap.** No simulator session was driven here.
- **The heartbeat has never been sent to a live server**: there are no credentials on this machine. What is proved
  is the body it builds (5 tests) and that it is wired into the one funnel every report goes through; what is not
  is that the dashboard shows the row, or that Plex accepts the transcode key it names.
- **The closing report** (`state: stopped`) depends on `reportStopped` reaching the funnel when the player closes —
  code-read, not observed. Until it arrives, the server's own reaper ends the row after its window.
- A heartbeat the account's **stream limit** refuses (`409`) is thrown and recorded, **not yet shown** as a player
  notice the way the web player's pill does. Recorded as the next refinement.
- `pushItemPosition` (the offline progress sync) still reports to `/:/timeline`; the heartbeat has no
  "record a position without a session" mode, so that path was left alone rather than given invented semantics.


## FIX — a Play that cannot start now says so; and the reason every Play did nothing (2026-10-25, Cline)

**Luther:** *"all is working now but clicking Play nothing happens"* → asked which tap, *"on ios every play button
is not working."*

### The cause — and it is not in this repository

Traced end to end, because the symptom was total: every Play button on every screen.

```
DetailActionsRow/Seerr header → PlaybackLauncher.play(...)
  → services.playback.queue(...)              (PlexMediaServices.queue)
  → PlayQueueRepository.createQueue(...)      → **POST /playQueues**
  → the WeFlix gateway refuses it             → PlaybackLauncher catches, debugPrint, returns → nothing at all
```

`/playQueues` was the **one call in the playback path the WeFlix gateway did not carry**: `app/api/plex/[...path]/route.ts`
exported `GET` and `PUT` only, and judged every non-GET against a write allow-list of a single path
(`/library/parts/<id>`). Every other call was already there — `/library/metadata/<key>`, the S5 transcode trio,
`/api/video`, `/api/transcode`. One refused call, every Play, every platform — and `PlaybackLauncher` printed the
error and returned, so the refusal reached nobody. That silence is this app's half of the bug.

### What this repository changed

| File | What |
|---|---|
| `Shared/Features/Player/PlaybackLauncher.swift` | `PlaybackPresenting` gained `reportPlaybackFailure(_:)`, and the queue's `catch` now calls it instead of only `debugPrint`ing. The error still goes to Sentry. |
| `Shared/Features/MainCoordinator.swift` | `PlaybackFailure` and `.handlesPlaybackFailures(_:)` live here, beside the state they draw — **deliberately not in a file of their own.** A new `Shared/` file would need an entry in the tvOS target's `Shared` allow-list, and that list is inside `weflix.xcodeproj/project.pbxproj`, which is carrying **Luther's in-flight signing/rebundle work**. `MainCoordinator.swift` is already in the allow-list, so this commit touches no file that is his. It also publishes `playbackFailure`. |
| `weflix-macOS/Features/AppModel.swift` | The Mac's own conformer publishes `playbackFailure` too. |
| `weflix-iOS`/`weflix-tvOS` `MainTabView.swift`, `weflix-macOS/Features/Main/MainView.swift` | The alert is applied alongside the existing `.handlesExternalPlaybackCallbacks`. |
| `Localizable.xcstrings` | `player.playbackFailed.title` ("Couldn't play this title") and `player.playbackFailed.message`, en/fr/zh-Hans. |

### The server half (Luther approved both)

Written and green in the **server** repository — a `POST` export on the generic gateway, `/playQueues` judged by its
own path and query rules (`type, uri, own, shuffle, repeat, continuous`), the client's synthetic
`server://weflix-gateway…` replaced by the real `PLEX_MACHINE_IDENTIFIER`, and the same library check the metadata
read makes run on the queued title. The full record is the top entry of
`plex-custom-frontend/checkpoints/CURRENT.md`. It is committed and **pushed**: the beta redeployed on that push and
serves it (measured — `/api/health` on `e39c19b`). **Production does not**, until `Development` is merged to
`Master`, which is Luther's call. The app itself is committed here but not pushed.

### Gate (measured, this Mac)

| Target | Command | Result |
|---|---|---|
| iOS | `-scheme weflix -destination 'platform=iOS Simulator,id=DD8FBFD3-…' -derivedDataPath build/DerivedDataIOS` | **BUILD SUCCEEDED**, 0 errors |
| tvOS | `-scheme weflix-tvOS -destination 'platform=tvOS Simulator,id=A533891E-…' -derivedDataPath build/DerivedDataTV` | **BUILD SUCCEEDED**, 0 errors |
| macOS | `-scheme weflix-macOS -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData` | **BUILD SUCCEEDED**, 0 errors |
| Tests | `xcodebuild test -scheme weflix-macOS …` | **TEST SUCCEEDED**, 420 cases passed, 0 failures |

The three builds used `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` (macOS as before, and now iOS/tvOS too:
without it this machine fails on **a SwiftPM bundle's Finder detritus** —
`AetherEngine_AetherEngine.bundle: resource fork, Finder information, or similar detritus not allowed` — an
environment condition, not this change; the same build without signing compiles and links cleanly).

**Recorded, not hidden:** the first full test run had two `PauseScreenPresentationTests` failures — each case took
~21 s under the build's load. In isolation that suite is **TEST SUCCEEDED** (0.3 s per case) and the full re-run is
**TEST SUCCEEDED** with 420 passes. Timing flakiness under load, not a behavioural failure.

**Luther's uncommitted work is untouched, by construction.** The bundle-id/app-group rename, the entitlements edits
and the **signing/team changes in `weflix.xcodeproj/project.pbxproj`** are his and are **not in this commit**. That
is why `PlaybackFailure` was not given a file of its own: a new `Shared/` file needs an entry in the tvOS target's
`Shared` allow-list, which lives in that same `project.pbxproj`. `MainCoordinator.swift` is already named there, so
this change needs no project edit at all — the file's `git diff` is, character for character, the state he left it
in (28 insertions, 19 deletions, all his).

### Not verified

- **The fix end to end.** The gateway change is not deployed (nothing is pushed), and this machine cannot drive a
  tap, so "press Play and the film starts" is unmade — it is exactly the confirmation `checkpoints/CURRENT.md`
  has carried since A1–A5 (lines 675, 677).
- The alert has never been seen: it needs a failed queue, which needs the un-deployed server half.
- `/:/timeline` is still refused by the gateway, so watch state will not save through it. Flagged for the next
  step, not changed here.



## CHANGE — the brand colour is WeFlix red `#E50914`, not the pink (2026-10-25, Cline)

**Luther:** *"can you change the main accent color to e50914 instead of that pink looking"*

It was `BrandPrimary` **and** `AccentColor` in the asset catalogs: display-P3 `(255, 66, 107)` — a pink. Both are now
**sRGB `(233, 9, 20)`** = `#E50914`, in `weflix-iOS`, `weflix-macOS` and `weflix-tvOS` — six colour sets, and the
tvOS `AccentColor`, which had been **empty** (no value at all), now carries the red too.

The colour space is switched to `srgb` rather than reusing `display-p3`: `#E50914` is an sRGB hex, and dropping its
components into a P3 set renders a different, more saturated red than the value asked for. Nothing else moved —
`BrandSecondary` (near-white), `BrandPrimaryForeground` (the near-black text laid on the brand colour) and
`Background` are untouched.

One change covers everything the accent reaches, because both `Color.brandPrimary` (asset symbol) and
`Color.accentColor` resolve from these sets: the selected tab, checkmarks and current-option marks
(`.selectionAccent`), the sign-in button, profile avatars, and the Seerr/requests controls.

**Measured:** iOS · tvOS · macOS **BUILD SUCCEEDED**, 0 errors; `xcodebuild test` **TEST SUCCEEDED**; and the
simulator shows the **Home** tab and its icon in the new red rather than the pink (screenshot this session). The
`Localizable.xcstrings` in the same commit only marks `seerr.request.action.modify` and
`seerr.requests.filter.completed` as Xcode-`stale`, which is the consequence of removing their last usages earlier
in the session.


## FIX — Settings for a friend: no Interface section, no Integrations, no licence row (2026-10-25, Cline)

**Luther:** *"for non admin account. in the profile when you click it. can you hide in the settings Interface, and the
whole intergration, Licenses"*

- **`WeFlixSessionController.isOwner`** — `GET /api/app/me`'s own `user.isOwner`, exposed on the controller the gate
  already hands down. It has to come from the server: the proxy grants a friend no admin bit at all, so there is
  nothing to infer from permissions.
- **`SettingsView`**, for a **non-owner**: the **Interface** row is gone, the **Integrations** section is gone (both
  the macOS row and the iPhone section), and the **Licences** row is gone. What stays: My account, Playback, Audio,
  Subtitles, Downloads, Storage.

**Flagged — and Luther confirmed it (2026-10-25): *"thats fine hide it"*.** The licence row is one of the two places
the GPL-3.0 notice lives (the other is `README.md`), and `docs/PROJECT.md` §6 records both as *part of the
deliverable, not decoration*. He was shown that a friend would no longer see it in the app and chose to hide it
anyway, so the row stays owner-only. `README.md` and `LICENSE` are untouched, so the distribution still carries the
licence.

**Not covered:** tvOS's own settings screen (`weflix-tvOS/Features/Settings/SettingsNavigation.swift` filters only
accounts and profiles). The ask was the iPhone profile menu; say the word and tvOS follows.

**Gate:** iOS · tvOS · macOS **BUILD SUCCEEDED**, 0 errors; `xcodebuild test` **TEST SUCCEEDED**.


## FIX — Discover: a title already asked for says so, and a title the library holds plays (2026-10-25, Cline)

**Luther:** *"ON THE DISCOVER, i click on movie i requested.. but i still see Request Button. this will confuse
people. this should be button says Requested and disabled. if the movie is available in the library that button
should be a play button."*

### Why a requested movie still offered **Request**

`SeerrMediaRequestAvailability.pendingRequest()` matched only a request with `status == .pending`, and **Overseerr
auto-approves by default**: the request sits at `.approved` while the *media* is still `.pending`, so the app saw
"no request of mine" — and, with the library not yet holding the title, `isRequestButtonHidden` was false. Result:
an enabled **Request** button above a **Requested** chip. Two different questions had been collapsed into one:
*has this account asked?* and *is it still waiting for a decision?*

### What the app does now

| The title | The button |
|---|---|
| **in the library** | **Play** — opens the library's own detail screen |
| **already asked for** by this account (pending **or** approved) | **Requested**, and **disabled** — nothing left to press |
| neither | **Request**, as before (with its quota/permission reasons) |

- `SeerrMediaDetailViewModel.ownActiveRequest` — this account's live request (anything not `.declined` and not
  `.completed`); `isRequested` is its answer, and it drives `requestButtonTitleKey` (`seerr.request.action.requested`
  → **Requested**, added in en/fr/zh), `isRequestButtonDisabled` and `isRequestButtonHidden`.
- **All three platforms** get the requested/disabled behaviour for free: the iOS, macOS and tvOS headers all read
  those view-model properties. tvOS's own detail view was missing `.disabled` and now has it.
- **Play**: `libraryRatingKey` is Overseerr's `mediaInfo.ratingKey` (Plex's own key, reported once the media is
  available) and `libraryItem(server:)` builds the library `MediaItem` for the active server — through a new
  one-place factory, `MediaItem.libraryEntry(...)`, which `WatchlistView` now uses too instead of its own copy.
  The button is offered **only** when the key and an open handler both exist, so it can never be a dead tap.
- Wiring: `SeerrMediaDetailView` gained an optional `onPlayInLibrary`; the iOS Discover stack passes the
  coordinator and gained the library `Route` destination, and `MainCoordinator.showMediaDetail` now appends for
  `.seerrDiscover` (it used to `break`, because nothing there could open a library title).

**Scope, stated plainly:** the **Play** button is **iOS only** for this step. macOS's own header and tvOS's own
detail view need their own navigation wiring (macOS routes Seerr through `AppModel`, tvOS through its own stack),
and a Play button there would be a dead tap until that is done. Requested/disabled applies everywhere.

**Not verified:** that the live Overseerr answers the proxied `/movie/{id}` with `mediaInfo.ratingKey`. No session
could be driven from this workstation (the app is signed in on the simulator, but this harness has no tap tool). If
it is absent, the Play button simply does not appear — that is the designed fallback, not a silent failure — and
the next step would be the server resolving the library key by TMDB id. Luther's check: open a title he has asked
for (**Requested**, greyed) and one the library holds (**Play**, opens the library screen).

**Gate:** iOS · tvOS · macOS **BUILD SUCCEEDED**, 0 errors; `xcodebuild test` **TEST SUCCEEDED**.


## FIX — the Requests screen: only the keys Overseerr's `/request` accepts (2026-10-25, Cline)

**Luther, after the menu work:** *"requests button on discover says Unknown querry parameter"*. Confirmed on the
iPhone 17 Pro simulator first (the menu itself was correct: `Settings · Downloads · My Watchlist · Favorites`,
then `Sign Out`), then fixed on both sides.

**What was wrong.** Overseerr validates `GET /request` strictly and answers
`400 {"message":"Unknown query parameter '<key>'"}` for a key outside its schema. `SeerrRequestRepository.getRequests()`
was sending `mediaType` and `sortDirection` — right for the discover rails, rejected here — so the list died on its
first call. The server proxy forwarded them; it now narrows that one path to `take`, `skip`, `filter`, `sort`
(+ the forced `requestedBy`), which is exactly what the web's own `seerrMinePath()` sends.

**App changes (so the two halves agree):**

- `SeerrRequestRepository.getRequests()` takes `take`, `skip`, `filter`, `sort` — the two unsupported keys are gone.
- `SeerrRequestsView`'s options menu keeps the **sort** picker and drops the **media-type** picker and the
  **oldest-first** toggle, and `optionsIcon` no longer reads them; `SeerrRequestMediaFilter` is deleted and
  `SeerrRequestQuery` loses `mediaType` and `isAscending`. The status chips stay.
- `SeerrRequestsViewModel`'s two reads send only the four keys.

- `SeerrRequestStatusFilter` is now **exactly** Overseerr's allowed set: `all, pending, approved, processing, failed,
  available, unavailable`.

**The second half of the same defect, measured live (2026-10-25).** Luther tapped **Completed** and Overseerr
refused it by name:

> `request.query.filter should be equal to one of the allowed values: all, approved, available, pending,
> processing, unavailable, failed`

So the app's chips carried **two values that can only ever fail** — `completed` and `deleted` — and they are gone.
Overseerr's own word for a fulfilled request is *available*, which the app already offered, so nothing was lost.
The refusal arrived as the Seerr alert on the screen (`Seerr / request.query.filter should be equal to one of the
allowed values: …`), which is the proxy relaying Overseerr's own body — the right behaviour: the real reason, not a
generic sentence.

**Gate after it:** iOS · tvOS · macOS **BUILD SUCCEEDED**, 0 errors; `xcodebuild test` **TEST SUCCEEDED**.


## PHASE APP WATCHLIST — My Watchlist and My Requests in the profile menu, and a simpler iPhone Settings (2026-10-25, Cline)

**Luther's five, for the iPhone:** *"1 clinking setting> remove profiles. 2 Accounts and server rename it to My
account. It shows your account details. no need fr toggle button and info icon. 3. remove \"remove the account\"
remove add plex or jellyfin 4. clickng profile icon add my watchlist and my request. 5. remove switch profile and
change to sign out"* — and, on being asked where the list lives, *"i have a watchlist o weflix.me data is saved
on postgress"*, which is right: the list is WeFlix's own `watchlist_entries`, per account.

### The one thing that was actually missing

The watchlist has lived on WeFlix since beta fix #2 (`watchlist_entries`, keyed by `profile_id`) and the web reads
it through `/api/plex-actions/watchlist` — **with the `weflixSession` cookie**. The native client authenticates
with its **device bearer token** through `/api/app/*`, and there was no `/api/app/watchlist`. So the list existed
and the app simply had no door to it; that door is built in the server repository, this same day.

### What the iPhone app does now

| # | Ask | Done |
|---|---|---|
| 1 | Settings → no **Profiles** | the `profiles.title` link is `#if os(macOS)` now; iPhone's Settings no longer lists Profiles |
| 2 | "Accounts and servers" → **My account**; account details; no toggle, no info icon | `settings.accounts.title` is **My account** (en `My account` / fr `Mon compte` / zh `我的账户`); on iPhone the server row is name + status only — the enable `Toggle` and the `info.circle` button are `#if !os(iOS)` |
| 3 | no "Remove the account", no "Add a Plex account or a Jellyfin server" | both are `#if !os(iOS)` |
| 4 | profile icon → **My Watchlist** only | `UserMenuView` lists My Watchlist. **Requests stay in Discover** — Luther, correcting the first pass: *"no need to add my request in the menu from profile icon. instead in the discover. theres a button Requests."* The Discover **Requests** button already exists and is **account-scoped by the server** (`lib/app-seerr-routes.ts`'s `appSeerrPlan()` forces `requestedBy` to the account's own Overseerr id on every list read), so nothing was added to the menu: the requests list shows this person's own requests, whoever they are |
| 5 | no Switch Profile → **Sign Out** | the Switch-profile section is gone; a destructive Sign Out runs `WeFlixSessionController.signOut()` then `SessionManager.forgetWeFlixAccount()` — the same pair the signed-in card uses |

**Where My Watchlist sits** (a second correction, 2026-10-25): *"on profile menu on ios dont separate the watchlist
from the other. put it above favorites."* It is **not** its own section — the menu's one list is Settings,
Downloads (when it is not a tab), **My Watchlist**, Favorites (when it is not a tab), with **Sign Out** in its own
section last. The menu's rows are: `Settings · Downloads · My Watchlist · Favorites` then `Sign Out`.

### The new screens

- **`My Watchlist`** (`weflix-iOS/Features/Watchlist/WatchlistView.swift`) reads `GET /api/app/watchlist` with the
  device token (`WeFlixWatchlistClient`) and draws a poster grid. A poster whose entry carries a library rating key
  opens the title (a `MediaItem` built from the key + the active server identity, handed to
  `MainCoordinator.showMediaDetail` exactly as the Favorites row does); one the library does not hold is shown but
  inert. The artwork is fetched through the gateway's `/api/image` **with the bearer header**
  (`WeFlixGatewayURL.artworkRequest`), because `AsyncImage` cannot set one.
- **`My Requests` is *not* in the menu** (corrected 2026-10-25). The requests live where they already were: the
  **Discover** screen's *Requests* button (`SeerrDiscoverView` → `SeerrRequestsView`). What makes that list "mine"
  is the **server**: the app's proxy forces `requestedBy` to the account's own linked Overseerr id on the
  `/request` read (`lib/app-seerr-routes.ts`), so a person sees exactly the requests they made — and a caller who
  happened to hold `MANAGE_REQUESTS` could not widen it. No app change was needed for that; the first pass's menu
  row (`MyRequestsView`) was removed.

### The sign-out door

`WeFlixSessionController` was a `@State` inside `WeFlixAppGate` and **not in the environment**, so the menu could
not reach it. The gate now adds `.environment(session)`, and the menu calls the same sequence — one sign-out, one
implementation.

### Gate (measured, this Mac)

| Target | Command | Result |
|---|---|---|
| iOS | `-scheme weflix -destination 'platform=iOS Simulator,id=DD8FBFD3-…'` | **BUILD SUCCEEDED**, 0 errors |
| tvOS | `-scheme weflix-tvOS -destination 'platform=tvOS Simulator,id=A533891E-…'` | **BUILD SUCCEEDED**, 0 errors |
| macOS | `-scheme weflix-macOS -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO` | **BUILD SUCCEEDED**, 0 errors |
| Tests | `xcodebuild test -scheme weflix-macOS …` | **TEST SUCCEEDED** |

**Not verified:** an eye and a tap on a device — this Mac has no browser session, no test account and no typing
tool, so "the menu shows both rows", "a poster opens the title" and "Sign Out returns to the sign-in screen" are
verified by the code, the builds and the server route's tests, not by a screenshot. Luther's checks: open the
avatar, see **My Watchlist** and **My Requests**; open the watchlist and see his own posters; sign out and land on
the sign-in screen.

**Note on the tree:** `Shared/Features/Seerr/SeerrDiscoverViewModel.swift`, `weflixTests/Features/Seerr/` and part
of `Localizable.xcstrings` were already modified in the working tree (the Seerr "show only what's in the library"
filter) before this work and are **not** part of it.


## MERGED — production now has the app's server half, so the app works again (2026-10-25, Cline)

**Luther, after the measurement in the entry below:** *"Merge Development → main now and watch weflix.me until it
serves the new commit — the app then works on production (also brings the requests feature)."*

Done, on his explicit word, and verified: `https://weflix.me/api/health` now serves
`f11a9e38731f906d3b6653c86adc40d9ecbd65a7` (the WEB merge of `Development` → `main`, recorded in the server
repository's `checkpoints/CURRENT.md` under **MERGED**). Measured on production after the deploy: the app's
routes, which were `404` before, are all present — `/api/app/stream-ticket` → **405** (it exists), and
`/api/app/seerr/api/v1/search` → **401** (it exists); and the existing web UI is unharmed (`/login` → `200` with
its title, `/signup` → `200`, `/requests` → `200`, no `5xx` on the player routes).

**What that means for the app**, and it is the honest reading of the two symptoms Luther reported in sequence:

- **Sign in → the library**, because the gateway is deployed. The dead end is gone for the real reason, not
  because the app hides it.
- **The requests tab appears only if his account has an Overseerr user linked** (`accounts.overseerr_user_id`,
  set in the web UI's Admin → Users → *Overseerr id*). If it is not set, the tab stays hidden and Settings →
  Integrations → Requests says *"Requests aren't set up for your account yet. Ask Luther."* — which, on a server
  that now has the feature, is finally the **true** sentence and one click to fix.
- The correction in `1095819` still matters and still applies: a WeFlix that *does* lack the app's library is now
  reported as such (*"This WeFlix server doesn't have the app's library yet…"*) and does not log anybody out.

**Not verified, and unchanged:** a signed-in run against production, because no test account exists here
(`.env.test.local` absent in the server repository) and no typing tool was available to drive the simulator. So
"sign in → the library" is verified at the level of *every route the app calls now exists on production and
answers as designed*, not by a screenshot of the library.


**Luther, after the previous correction:** *"it says your signin has ended. sign in again."*

**Measured, and it is not the app.** `weflix.me` (production) is built from `main`, and `main` **never received
the PHASE APP-GATEWAY server work**:

```text
origin/main = 5428f0e "Merge pull request #4 from heylucifurr/Development"
  S1 ccda26b (the gateway accepts the app's bearer token)  -> NOT an ancestor of main
  S5 a7f6fde (the stream ticket)                           -> NOT an ancestor of main
  S6 01fdff7 (the client's own read keys)                  -> NOT an ancestor of main

production routes:   /api/app/me -> 401        (the sign-in phase IS deployed)
                     /api/app/auth/login -> 405
                     /api/app/stream-ticket -> 404   <-- the gateway phase is not
                     /api/plex/identity -> 401
```

So on production the app **signs in fine** and then every library read is refused, `ServerRegistry` marks the link
`.needsReauthentication`, and the app said **"Your WeFlix sign-in has ended. Sign in again."** — which is false:
the person had just signed in and `GET /api/app/me` had answered with their own name. This behaviour predates this
task (it came in `e54a22b`, 2026-10-24) and it is the same gap a previous session already recorded in
`c617662` — *"the production deploy gap that blocks the app … the merge is the one action that makes the app work
against production. Agents do not merge to `main` — this is Luther's call."*

### The fix: the app no longer blames the sign-in for a deploy gap

`WeFlixAppGate.handleGatewayRefusal()` tells the two apart before saying anything, and the discriminator is the
app's own endpoint — `/api/app/stream-ticket`, which exists on every WeFlix that has the app's library and answers
`404` on every WeFlix that does not (measured above; the route itself only ever answers `401` or `200`, so a `404`
can only mean "not deployed"):

| What the server did | What the app says |
|---|---|
| `401` on the gateway, `/api/app/stream-ticket` **present** — a revoked token, or a **pending/disabled** account | *"Your WeFlix sign-in has ended. Sign in again."* (unchanged, and still right) |
| `401` on the gateway, `/api/app/stream-ticket` **404** — this WeFlix has no app library at all | *"This WeFlix server doesn't have the app's library yet. Ask Luther to update WeFlix."* — **and the person stays signed in**, on the signed-in card, with Sign Out |

A network failure, or any refusal other than a `404`, keeps the old behaviour, so a train tunnel cannot be
mistaken for a deploy gap. `WeFlixSignedInView` gained an optional `notice` so that sentence has somewhere to
live (the sign-in form is the wrong place: the person is still signed in).

**This does not make the library work on production** — nothing in the app can, because the server side is not
deployed there. It stops the app from saying something untrue and from looping. Making it work is the
`Development → main` merge, which is Luther's call and was not made.

Gate: iOS simulator **BUILD SUCCEEDED** · tvOS **BUILD SUCCEEDED** · macOS **BUILD SUCCEEDED** (0 errors each) ·
`xcodebuild test -scheme weflix-macOS` **TEST SUCCEEDED, exit 0**.


**Luther, minutes after the previous entry was pushed:** *"what the hell happened?? this is wrong
implimentation. when i sign it says Request arent setup for this account .... THIS IS WRONG. put back the previous
working. This is not what i want. CRITICAL ERROR"*

**He was right, and the cause was mine.** The previous commit made the **requests the signed-in screen**. The app
ships pointed at `https://weflix.me` — production — and production is at `5428f0ea`, which **does not have the
server half of this feature**. Measured, not assumed:

```text
prod  https://weflix.me/api/health                      -> commit 5428f0ea…      (main was not merged)
prod  /api/app/seerr/api/v1/search                      -> 404                   (the route does not exist there)
beta  the pre-production deployment's /api/health        -> commit 940fc3a…
beta  the pre-production deployment's seerr search       -> 401                   (the route exists)
```

So on production `GET /api/app/me` carries no `requests` block, it decoded as `nil`, and one flag collapsed
*"the server has not answered"* with *"this account is not linked"* — which is why a signed-in person was told
**"Requests aren't set up for your account yet. Ask Luther."** by a server that had never heard of requests. A
signed-in app whose *only* screen was a dead end. That is the whole bug, and it was a design error, not a
typo: **I made the app's default screen depend on a server change that was not deployed.**

### What is restored

The **previous working main screen is back, exactly**: sign in → the library (`MainTabView` / `MainView` /
tvOS `MainTabView`), with the requests reachable inside it through the Seerr tab and the sidebar entry, which
appear only when the server says this account may use them.

`weflix-iOS/Features/ContentView.swift`, `weflix-macOS/ContentView.swift`, `weflix-tvOS/ContentView.swift` and
`Shared/Features/Auth/WeFlixAccount/WeFlixSignedInView.swift` are **byte-identical to `2b0e68c`** (verified:
`git diff 2b0e68c -- <those files>` is empty). `WeFlixAppGate`'s `content` is back to the old switch
(spinner → sign-in → library-when-ready / activation / signed-in card); the only additions to it are ones that
cannot change what it shows: the `SeerrStore` reference, the `requests` adoption, the `.weflixSignInEnded`
observer, and clearing the requests on a sign-out. `WeFlixRequestsRootView.swift` — the wrapper that made the
requests the root — is **deleted**, and its `project.pbxproj` entry with it.

### What is fixed, so it cannot happen again

`SeerrStore` no longer has one flag. `requestsState` has three values, and the app says three different things:

| `requestsState` | When | What the app says |
|---|---|---|
| `.unknown` | no answer yet: a launch in flight, **or a WeFlix that predates the feature** | *"This WeFlix server does not have requests yet. Ask Luther to update WeFlix."* |
| `.notLinked` | the server answered, and the account has no linked Overseerr user | *"Requests aren't set up for your account yet. Ask Luther."* |
| `.enabled` | the server answered, and this account may browse and request | the requests UI appears; Settings says *Connected via WeFlix* |

**A server that has not been updated is never reported as the account's fault again**, and no screen of this app
is a dead end: the signed-in screen is the library, which does not depend on requests at all.

### Gate

iOS simulator **BUILD SUCCEEDED** · tvOS **BUILD SUCCEEDED** · macOS **BUILD SUCCEEDED** (0 errors each) ·
`xcodebuild test -scheme weflix-macOS` **TEST SUCCEEDED, exit 0**. Simulator: built, installed and launched on
the iPhone 17 Pro; the runtime UI snapshot shows the sign-in screen on a fresh launch (no stored token, and no
typing tool or test credential was available to me to drive a sign-in — so the *signed-in* screen is verified by
the git-identical restore above, not by a screenshot).

### Kept from the previous commit

Everything that does not depend on the server half being deployed: the bearer-only proxy client
(`SeerrNetworkClient` → `WeFlixServer.seerrBaseURL`), `SeerrStore`, `SeerrAccountRepository`, the deletion of
Seerr's own sign-in/address/key/cookie plumbing, the plain-language errors and the `401` → sign-in screen, the
read-only Settings row, **Settings → Licences** and the README attribution, and the removal of the test site's
address from this repository. The **server** half stays on WEB's `Development` (deployed to the pre-production
deployment); turning the feature on for everyone is the `Development → main` merge, which is Luther's call and
was not made.


**The delivery:** *"A friend installs the WeFlix app, signs in with their WeFlix account, and can browse requests
and request movies/shows immediately, with no setup."* The client half is in `a23a421`; the server half is in the
other repository's `578cc6f` (see its `checkpoints/CURRENT.md`).

### What changed, in one paragraph

The **main screen after sign-in is the requests**, not the library. It used to be the library, which needed a
`SessionManager` that had adopted a Plex-shaped account and connected a server; now it is the thing a friend can
actually use — the existing discover/search experience, a title's details, the request sheet, the requests list
and the quota — with **Sign Out** in the toolbar (iOS, iPadOS, macOS) or on a Settings tab (tvOS).
`GET /api/app/me` answers a new `requests` block (`enabled`, the account's Overseerr user id, the permission bits
the server grants), and `SeerrStore.adopt()` is the one thing that turns the requests UI on. Library browsing is
a later task, and `MainTabView`/`MainView` stay compiled and unreachable, exactly as they were.

### The app holds no Overseerr credential, address or session

`SeerrNetworkClient` speaks to `WeFlixServer.seerrBaseURL` — `https://weflix.me/api/app/seerr` — with the device's
WeFlix bearer token. The server adds the Overseerr address, the API key and `X-API-User`, and decides who the call
acts as. Four things were **deleted** rather than left unreachable, because leaving them would be a trap:

| Deleted | What it did |
|---|---|
| `Shared/Features/Integrations/SeerrSessionService.swift` | validated an Overseerr address, ran the Plex/local/Jellyfin sign-ins, deleted Seerr cookies on sign-out |
| `Shared/Features/Integrations/SeerrViewModel.swift` | the setup screen's model: a base-URL field and three sign-in methods |
| `Shared/Repository/Seerr/SeerrAuthRepository.swift` | `/status`, `/auth/plex`, `/auth/local`, `/auth/jellyfin`, `/auth/me` — replaced by `SeerrAccountRepository` (the quota read, and nothing else) |
| `Shared/Models/Seerr/SeerrAuthRequests.swift` | the three auth bodies |

The five remaining Seerr repositories **no longer take a base URL at all** (`init(session:)`), so there is nowhere
left to point them, and `SeerrStore.baseURLString` — a `UserDefaults`-backed, user-editable address — is now
`SeerrStore.baseURL`, a computed constant. `SeerrRequestFormatting.avatarURL` no longer builds a URL out of the
base either: Overseerr's relative `/avatar/…` path is `nil` now, because an image request cannot carry the token
and *nothing calls Overseerr directly*. (Absolute avatars — TMDB, Gravatar — still load.)

### Errors a person can act on

`SeerrAPIError` gained `.signInAgain`, `.unreachable` and `.refused(sentence)`, and one `seerrSentence()` replaced
five copies of the same `integrations.seerr.error.connection` switch. A `409` now reads **"Requests aren't set up
for your account yet. Ask Luther."** (the server's own sentence), an already-requested title reads as Overseerr's
own words, a quota refusal as its own, and a `401` is "Please sign in again." — and it posts `.weflixSignInEnded`,
which `WeFlixAppGate` turns into the sign-in screen, because a `401` from the proxy means the *whole app* is
signed out, not just that screen.

### Settings, and the licence

`Settings → Integrations → Requests` is now read-only: **"Connected via WeFlix"** (or *not set up for your
account yet*) plus the account's own quota. The address field, the "start setup" button, the three sign-in methods
and the Seerr sign-out are gone — signing out of WeFlix is the app's only sign-out and lives on the main screen.

**GPL-3.0:** `README.md` carries *"WeFlix for Apple is a modified version of Strimr by wunax
(https://github.com/wunax/strimr), licensed GPL-3.0. Modified by Luther, 2026."*, and the same notice is now
inside the app, at **Settings → Licences** (`Shared/Features/Settings/LicencesView.swift`, and a `licences`
category in tvOS's settings sidebar). `LICENSE` and every original Strimr notice are untouched.

### The test site's address is gone from this repository

Searched and replaced **every** occurrence of it and of the Plex backend's hostname (seven: two in
`Shared/Config/WeFlixServer.swift`, one in `docs/PROJECT.md`, one in `weflixTests/…/WeFlixLiveAuthTests.swift`,
three in this file). Both are now referred to by name and never by address — including in this entry, which had to
be fixed twice while being written. The command and its (empty) output are in the report.

### Gate

| Target | Command | Result |
|---|---|---|
| iOS simulator | `-scheme weflix -destination 'id=DD8FBFD3-E3DC-4F4F-BCF2-1667EF50A8C0'` (iPhone 17 Pro) | **BUILD SUCCEEDED**, 0 errors |
| tvOS simulator | `-scheme weflix-tvOS -destination 'id=A533891E-0975-4902-9057-0F1E30BEDF90'` | **BUILD SUCCEEDED**, 0 errors |
| macOS | `-scheme weflix-macOS -destination 'platform=macOS,arch=arm64'` + `CODE_SIGNING_ALLOWED=NO` | **BUILD SUCCEEDED**, 0 errors (no Mac development profile for `me.weflix` on this machine) |
| Tests | `xcodebuild test -scheme weflix-macOS -destination 'platform=macOS,arch=arm64'` | **TEST SUCCEEDED, exit 0** — 415 tests. `WeFlixLiveAuthTests`' success-path test now compares `me.user` and checks the new `requests` block arrived |

**Simulator, measured:** the app was built, installed and launched on the booted iPhone 17 Pro. The runtime UI
snapshot (`snapshot_ui`) and a screenshot both show the first screen is **"Sign in"** / *"Use your WeFlix
account."* with a *Username or email* field and a *Password* field — no "Choose a service", no Plex or Jellyfin
button. `Shared/Features/Auth/WeFlixAccount/WeFlixSignedInView.swift` (the old "signed in as …" placeholder) is
deleted: the requests root owns that screen now.

### Not verified, and why

**Everything in the simulator test that needs a signed-in account.** The brief says test credentials come only
from the server repository's `.env.test.local` (`WEFLIX_TEST_USER`, `WEFLIX_TEST_PASSWORD`), and that file **does
not exist** in `plex-custom-frontend` (checked: `.env.test.local`, `.env.local`, `.env.test` are all absent). It is
gitignored (`.gitignore` line 34, `.env*`), and no credential was invented, guessed or asked for. So these are
**not verified**, on the app side and the server side alike:

- wrong password → the error sentence on the sign-in screen;
- sign in → the requests screen (discover rails, search, a title's details);
- requesting a title, and the request appearing **under the test user** in Overseerr;
- deleting that test request through Overseerr's API;
- relaunching and staying signed in;
- Settings showing "connected via WeFlix" and Licences **on a signed-in device**;
- Sign Out → back to Sign in.

What *is* verified without a credential, on the live pre-production deployment: its `/api/health` serves the
server commit, and the new proxy route exists and is bearer-only — no token `401`, a cookie instead of a bearer
token `401`, a well-shaped but unknown bearer token `401`, `POST` `401` (commands and output in the report, which
names the host because a curl transcript is not this repository).

### Questions for Luther

1. **The merge to `main` did not happen.** The brief authorises `Development → main` *"ONLY after every WEB gate
   passes and the beta curl checks pass"*. The gates pass; the curl checks need the test account, which does not
   exist here. **Nothing was merged, and `main` is untouched.** Say the word once `.env.test.local` exists (or if
   you want the merge without the live proof) and it is a normal merge, no force-push.
2. **`WEFLIX_BASE_URL` / `WEFLIX_TEST_BASE_URL` still exist** as an https-only environment override in
   `WeFlixServer.baseURL` and in the live tests. The brief says the app uses `https://weflix.me` "only, from ONE
   config constant"; the override *is* that one constant, it is unset in every shipped configuration, and removing
   it would delete the only way the live tests can be pointed at the pre-production deployment. **Kept, and it now
   names no host.** Tell me if you want it gone and I will remove it and the live tests' base-URL hook with it.
3. **Editing a request is not allowed through the proxy.** The brief's allow-list names `POST /request`, own
   requests and cancelling one's own pending request — not `PUT /request/<id>`, which is Strimr's "update a pending
   request" and which the web app never had either. So `PUT` is a `404`, and the request sheet's "Update" path
   would show *"That isn't available in the app."* If you want editing, it is one line in the server's allow-list
   plus one in the app.
4. **The requests badge on the discover screen is always 0.** `SeerrDiscoverViewModel.requestsBadgeCount` counts
   *pending* requests and is gated on `MANAGE_REQUESTS`, which the server deliberately does not grant this app.
   Left alone: changing what that number means is a decision, not a side effect.
5. **Overseerr's relative avatars do not load** in the app (see above); absolute ones do. Making them work needs an
   image path on the proxy that can be authorised without a header, which is a new decision rather than a fix.
6. **The app's `requests` block is a superset of the brief's `{ enabled }`.** It also carries `overseerrUserId`
   and `permissions`, because the client's request button, its "is this mine?" checks and its permission-driven
   gates cannot work without them. Both are already visible to the app inside every `/request` row's
   `requestedBy.id`, and neither is authority: the proxy ignores anything the client sends about who it is.
7. **Six WEB test failures pre-date this work** and are untouched (see the server repository's checkpoint): they
   are `isDirectRun`/Windows-path cases and date-dependent stats cases, and they fail identically at `7a01aec`
   with this task's two edited files reverted — measured, not assumed. Out of scope, so not fixed.

**Luther:** *"i check sample user on simulator. i notice theres no movie posters or images. then i logged in to my
account. same. then i click one movie then it says server unavailable."* Three unrelated causes, all found by
measuring on the simulator rather than reasoning from the code. Fixed in `ebbca0f` (client) and `01fdff7` (server).

### 1. No artwork: a card could not find its server

`ServerIdentity` is the key `ServerRegistry` stores a server under, and **every media item carries the context's
`serverIdentifier` as its server**. The account fix two rounds earlier made the registry's identity per account
(`weflix-gateway.weflix:2`) but left the resource's identifier as the plain machine identifier, so a card asked for
"the artwork service of server `weflix-gateway`" and found nothing — no placeholder request, no network traffic.

Measured: the app's own cache had **`artwork: 0`** rows while `media: 179` had been fetched, and no artwork URL was
ever requested. `selectGateway(accountID:)` now receives the same string as the registry identity, and
`testTheGatewayResourceIdentifierIsTheIdentityTheItemsCarry` pins the invariant. After the fix: **34 artwork rows**,
17 fetches, all `200`.

### 2. Artwork carried no credential

Five places download images themselves — `ArtworkResourceView` (a `.url` resource), `CachedArtworkService`,
`CachedLibraryService`'s previews, `ImageCornerColorSampler`, `DownloadManager` — and only one had been taught the
bearer header. They now share `WeFlixGatewayURL.artworkRequest(for:)`, which adds it **only** for WeFlix's host.

### 3. A loop that starved the app

`WeFlixAppGate` had two `.task` modifiers attached to a view whose *type* changes as the sign-in state moves
(spinner → form → signed-in), so every state change tore the subtree down and restarted both tasks: measured
`GET /api/app/me` six times in ninety seconds, adoption re-saving the account each cycle, and every other request
cancelled mid-flight — leaving a home screen served entirely from cache. One stable container (`ZStack { content }`),
one `.task`, and adoption driven by `.onChange(of: session.status)`.

### 4. The detail screen: the gateway refused the app's own query keys (server, `01fdff7`)

```text
before   /api/plex/library/metadata/4292?checkFiles=1&includeStreams=1&includeChapters=1&includeMarkers=1&includeOnDeck=1
             -> 400 {"error":"Unsupported Plex query"}      ← the app showed "server unavailable"
         /api/plex/library/metadata/4292?includeMarkers=1
             -> 200
after    the app's exact request -> 200 (verified on beta once the deploy finished)
```

The whitelist was written from the *browser's* traffic; `MetadataRepository` sends five switches and only
`includeMarkers` was on it. Added, all Plex's documented switches: `checkFiles`, `includeStreams`,
`includeChapters`, `includeOnDeck`, `includeMeta` (browse), `contentDirectoryID` (hub rows), `title` (subtitle
search). Credentials stay refused, and an unanticipated key still is too.

### Diagnostics, and how they were removed

`log show` in the simulator did not surface the app's `NSLog`, so the probes wrote a file in the app's container
(`Documents/weflix-diag.log`) that could be read from the host — that is how the loop counts, the identity
mismatch, and the artwork path were measured. **Every probe was deleted** (`Shared/Features/Auth/WeFlixAccount/WeFlixDiag.swift` no
longer exists) and the shipped tree is verified clean of them.

### Gate

macOS suite **exit 0** (416 cases, including 19 in `WeFlixGatewayURLTests`) · iOS signed build 0 errors ·
tvOS build 0 errors · server tsc 0, 28/28 in the gateway/proxy suites, lint 21 (9/12) = baseline · beta deployed
`01fdff7` and answers the app's detail request with `200`.

### Still not proved by a tap

Opening a title **in the app** and pressing play. This harness has no tap/type tool and macOS refuses `osascript`
keystrokes, so the two remaining confirmations are Luther's: a poster on the home screen, and a film playing. What
is proved: the library renders, artwork fetches 200 and is cached, the detail request the screen depends on is
answered by the gateway, and a real 3.1 GB direct play streams through `/api/video` with a ticket.


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

### The dead end on the home screen, fixed too (`e54a22b`)

"Your servers did not respond" offered nothing to act on. The app is a WeFlix client with one sign-in, so there is
exactly one useful answer: `WeFlixSessionController.reportSignInEnded()` clears the dead token, says *"Your WeFlix
sign-in has ended. Sign in again."*, and returns to the sign-in screen — and `WeFlixAppGate` calls it when
`ServerRegistry` marks the WeFlix account `.needsReauthentication` (which the registry already does when a request
is answered `401`, and `connectGateway` does when the account has no token to connect with).

### Still open (needs Luther's answer, not more code)

If the home says something is wrong after this, the reason is now **Melvie's account**, not the wiring: a pending
or disabled WeFlix account is refused by the gateway (`401`), so the app will now say the sign-in has ended and ask
for it again rather than blaming the network. The discriminating check: sign in as Melvie **in a browser on the
pre-production WeFlix deployment** — if the web UI shows her no libraries either, the account itself needs approving, and the app is behaving
correctly. What the app should do *instead* of asking for a sign-in (show the server's own sentence — "your account
is waiting for approval") is worth doing with that evidence in hand.


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
launch app (SIMCTL_CHILD_WEFLIX_BASE_URL=<the pre-production WeFlix deployment>)
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
| Live tests | the same, with `WEFLIX_LIVE_TESTS=1`, `WEFLIX_TEST_BASE_URL=<the pre-production WeFlix deployment>` and Luther's account in the scheme's test action | **exit 0 — all 15 passed**, including the whole cycle through the client: sign in → `me` → logout → `me` refused |

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





