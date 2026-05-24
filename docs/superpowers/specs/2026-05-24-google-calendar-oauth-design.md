# Google Calendar OAuth Integration — Design

**Date:** 2026-05-24
**Status:** Approved (pending spec review)
**Author:** Nikhil Patel (with Claude)

## Summary

Add Google Calendar as a second event source in Tardy, connected directly via
Google OAuth, alongside the existing macOS Calendar (EventKit) source. The two
sources run together; their events are merged and de-duplicated. Google's
structured `conferenceData` gives more reliable join links than the regex
scraping EventKit forces today, and direct OAuth lets users connect Google
without first adding their account to macOS System Settings.

## Goals

- Let users connect Google Calendar directly inside Tardy (no macOS
  system-calendar setup required).
- Extract richer, structured conference data (Meet links, dial-ins) from Google.
- Keep EventKit working; merge both sources and de-duplicate overlapping events.
- Distribute publicly and safely (no real secret shipped in the binary).
- Keep Google data acceptably fresh without running a backend.

## Non-Goals

- Push/`events.watch` real-time sync (requires an HTTPS webhook = backend). Out
  of scope; noted as a future option if a server is ever added.
- Per-calendar selection UI (v1 reads all of the user's calendars, matching
  current EventKit behavior). Deferred to v2.
- Multiple Google accounts at once (v1 supports a single connected account).
- Write access to calendars. Tardy is read-only.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Source model | EventKit **and** Google, merged + de-duped | User wants both; direct connect for some, EventKit for iCloud/Outlook/Exchange users |
| Auth implementation | **GoogleSignIn SDK for auth only**; hand-rolled REST | SDK handles the security-sensitive OAuth/refresh/Keychain; we avoid the giant generated Calendar API client |
| OAuth client type | **Apple-platform (iOS-type) client — no client secret** | Public client + PKCE; nothing sensitive shipped in the binary |
| Scope | `https://www.googleapis.com/auth/calendar.readonly` | Lets us enumerate calendars and read events; *sensitive* (not *restricted*) so no CASA audit |
| Freshness | Poll-based: existing cadence + `syncToken` + adaptive near-term polling + poll-on-open | No backend; push requires an HTTPS webhook |
| De-dup key | `iCalUID` (primary), `(startDate, normalizedTitle)` (fallback) | `EKEvent.calendarItemExternalIdentifier` == Google `event.iCalUID` for synced events |

## Architecture

Today `CalendarService` does two jobs: orchestration (poll timer, midnight
rollover, wake / timezone / day-change handling) and EventKit specifics. We
split these so event sources become pluggable.

```
                    ┌─────────────────────────────────────┐
   AppDelegate ◄────┤ EventCoordinator                     │
   (delegate        │  • owns all timers (poll/midnight/   │
    unchanged)      │    wake/tz) — lifted from today's    │
                    │    CalendarService                   │
                    │  • fetches from all enabled providers │
                    │  • merges + de-dupes → [UpcomingEvent]│
                    │  • adaptive near-term polling         │
                    └───────────┬──────────────┬───────────┘
                                │              │
                   ┌────────────▼────┐  ┌──────▼─────────────┐
                   │ EventKitProvider│  │ GoogleCalProvider  │
                   │ (today's EK code)│ │ (GoogleSignIn auth │
                   │                 │  │  + hand-rolled REST)│
                   └─────────────────┘  └────────────────────┘
```

### Components

**`EventProvider` (protocol)**
- `func fetchEvents(start: Date, end: Date) async throws -> [UpcomingEvent]`
- A change signal (delegate/closure) so a provider can ask the coordinator to
  re-poll immediately (EventKit fires `EKEventStoreChanged`; Google has no push
  and simply rides the coordinator's cadence).
- `var isEnabled: Bool` — whether the source is currently active.

**`EventCoordinator`** (refactored from `CalendarService`)
- Owns all timers and system-notification handling that exist today (poll =
  300s, midnight rollover, wake, timezone, day-change). This preserves the
  v0.1.x reliability work; it is relocated, not rewritten.
- Holds the list of enabled `EventProvider`s. On each refresh: fetch from all,
  merge, de-dupe, and notify `AppDelegate` via the **existing
  `CalendarServiceDelegate` contract** (renamed `EventCoordinatorDelegate`, same
  shape). `App.swift` changes minimally.
- Implements adaptive near-term polling (below).

**`EventKitProvider`**
- The current EventKit fetch/filter logic, moved behind `EventProvider`.
- Continues to expose `iCalUID` via `EKEvent.calendarItemExternalIdentifier`.

**`GoogleCalProvider`**
- Uses `GoogleAuthService` (GoogleSignIn wrapper) for a valid access token.
- Hand-rolled REST via `URLSession`:
  - `GET /calendar/v3/users/me/calendarList` → calendar IDs.
  - `GET /calendar/v3/calendars/{id}/events?singleEvents=true&orderBy=startTime&timeMin&timeMax` (and `syncToken` on subsequent polls).
- Maps to `UpcomingEvent` (see Conference Extraction + Filtering).

**`GoogleAuthService`** (thin wrapper over GoogleSignIn)
- `signIn(presenting:)` — runs the consent flow; GoogleSignIn handles PKCE, the
  `ASWebAuthenticationSession` presentation, token storage (Keychain), and
  refresh.
- `validAccessToken() async throws -> String` — returns a fresh token,
  refreshing as needed. Throws `needsReauth` if refresh fails (revoked or
  7-day testing-mode expiry).
- `signOut()` — disconnect + clear stored credentials.
- `currentAccountEmail: String?` — for the settings UI.
- Wrapped behind a protocol so tests substitute a fake.

> **macOS presentation note:** Tardy is an accessory app (`LSUIElement`, no dock
> icon, no main window). GoogleSignIn needs a presenting anchor for
> `ASWebAuthenticationSession`. The Connect flow is initiated from the Settings
> window, which provides the anchor; if no window is available, present from a
> transient key window.

### `UpcomingEvent` changes

Add:
- `source: EventSourceKind` (`.eventKit` | `.google`)
- `iCalUID: String?` (de-dup key)

`hasChanged(comparedTo:)` and equality (id-based) are unchanged.

## Auth Flow (GoogleSignIn, no-secret client)

1. User clicks **Connect Google Account** in Settings.
2. GoogleSignIn opens Google's hosted consent screen (`ASWebAuthenticationSession`)
   with scope `calendar.readonly`, using the Apple-platform OAuth client
   (**no client secret**; PKCE only).
3. On success, GoogleSignIn stores tokens in Keychain and exposes an
   auto-refreshing access token.
4. `GoogleCalProvider` calls `validAccessToken()` before each fetch.
5. On refresh failure → `needsReauth`: mark Google disconnected, surface a
   "Reconnect Google" state in Settings (and menu bar), keep running on
   EventKit.

**Why distributing this is safe:** the Apple-platform client has no secret; the
client ID is public by nature (visible in the consent URL). PKCE secures the
exchange. Tokens are per-user, minted only after that user consents, and stored
in that user's Keychain — nothing in the binary can expose another user's data.

## Data Freshness (no backend)

1. **Existing cadence** — rides the coordinator's 300s poll plus re-fetch on
   wake / timezone / day-change.
2. **Incremental `syncToken`** — Google `events.list` returns a `syncToken`;
   subsequent polls send it back and receive only changes, keeping quota low.
3. **Adaptive near-term polling** — as an event approaches its alert lead time,
   poll that window every ~30–60s so a last-minute reschedule, cancellation, or
   changed Meet link is caught before the takeover fires (consistent with the
   v0.1.9 "drop alert if the meeting ended" rule).
4. **Poll-on-open** — re-fetch when the menu-bar dropdown or Settings opens.
5. **Push (`events.watch`)** — out of scope (needs HTTPS webhook/backend).

Worst-case staleness: ~5 min for a far-off event; seconds for an imminent one.

## De-duplication

When a Google account is also synced into macOS Calendar.app, the same meeting
arrives from both providers.

- **Primary key:** `iCalUID` — `EKEvent.calendarItemExternalIdentifier` matches
  Google's `event.iCalUID` for synced events.
- **Fallback key:** `(startDate, normalizedTitle)`.
- **On match:** prefer the **Google** copy (richer structured `conferenceData`).

## Conference Extraction (the "better data" win)

For Google events, resolve the join target in priority order:
1. `conferenceData.entryPoints[type == "video"].uri`
2. `hangoutLink`
3. Fallback to the existing `ConferenceLinkExtractor` over description/location.

Phone: `conferenceData.entryPoints[type == "phone"]`. This is structurally more
reliable than the regex scraping EventKit forces today.

### Filtering (mirror EventKit rules)

Skip: all-day events (`start.date` rather than `start.dateTime`), cancelled
(`status == "cancelled"`), and declined (self attendee
`responseStatus == "declined"`).

## Settings UI

New "Google Calendar" section in `SettingsView`:
- **Connect Google Account** button → consent flow.
- When connected: show account email + **Disconnect**.
- "Needs re-auth" state if a refresh fails.
- `SettingsManager` persists the enabled flag (and, in v2, selected calendars).

v1 reads all of the account's calendars, matching current EventKit behavior.

## Error Handling

- **User cancels consent** → stay disconnected, no-op.
- **`401`** → refresh once (GoogleSignIn), then `needsReauth` if still failing.
- **`403` / quota** → exponential backoff; keep last-known events.
- **Network errors** → keep last-known events, retry next poll. Never clear
  events on a transient failure.
- Tardy always degrades gracefully to EventKit-only.

## Distribution & OAuth Verification

This is the only part that touches a website, and only static pages — no backend.

### One-time Google Cloud setup
- Create a Cloud project; enable the Google Calendar API.
- Configure the OAuth consent screen (User type: External; scope
  `calendar.readonly`; support + developer contact email).
- Create an **Apple-platform OAuth client** for bundle ID `com.nikp29.tardy` →
  client ID + reverse-client-ID redirect scheme.
- Register the reverse-client-ID URL scheme in `Info.plist` via
  `scripts/build-app.sh` (`CFBundleURLTypes`).

### Two rollout gates

**Gate 1 — Testing mode (build + beta now; no website):**
- Up to 100 named test users; they click through the "unverified app" screen
  once. Refresh tokens expire after 7 days (handled by the re-auth flow).
- Sufficient for development, dogfooding, and small beta.

**Gate 2 — Verification for public release (static site required):**
Because `calendar.readonly` is *sensitive*, publishing to Production without the
warning and 100-user cap requires Google verification:
1. Verified domain (ownership via Search Console) — e.g. GitHub Pages custom
   domain.
2. App homepage (public page).
3. Privacy policy (public page): "Tardy reads upcoming calendar events to show
   reminders; data never leaves your device."
4. App logo (brand verification, ~days).
5. Scope justification in the verification form.
6. Demo video (YouTube) showing the consent flow + scope in use.

Timeline: brand/logo ~days; sensitive-scope review days-to-weeks. **`calendar.readonly`
is sensitive, not restricted, so no third-party CASA security assessment is
required** (that applies to restricted scopes like Gmail).

## Testing Strategy

**Unit tests (fully offline):**
- PKCE handling is delegated to GoogleSignIn (not re-tested).
- Token/`needsReauth` handling via a fake `GoogleAuthService`.
- Google JSON → `UpcomingEvent` mapping: conferenceData priority, `hangoutLink`
  fallback, phone extraction, and all-day/cancelled/declined filtering.
- De-dup: `iCalUID` match, `(start, title)` fallback, prefer-Google.
- `URLSession` behind a protocol; Keychain/auth behind a protocol — no live
  network or real auth in tests.

**Manual checklist:**
- Connect account → Google events appear and merge with EventKit (no dupes).
- Disconnect → Google events disappear, EventKit remains.
- Token refresh after expiry → silent.
- Revoke access externally → "Reconnect Google" state appears; EventKit keeps
  working.

## Dependencies

- Add `GoogleSignIn-iOS` (SwiftPM; supports macOS) to `Package.swift`. Single
  focused dependency for auth only. No `GoogleAPIClientForREST`.

## Rollout / Sequencing

1. Refactor `CalendarService` → `EventCoordinator` + `EventKitProvider` (no
   behavior change; tests green).
2. Add `UpcomingEvent.source` / `iCalUID`; implement de-dup in the coordinator.
3. Google Cloud project + OAuth client + `Info.plist` URL scheme.
4. `GoogleAuthService` (GoogleSignIn wrapper) + Settings connect/disconnect UI.
5. `GoogleCalProvider` (REST + mapping + filtering) behind a feature gate.
6. `syncToken` + adaptive near-term polling + poll-on-open.
7. Beta in Testing mode; then pursue Gate 2 verification for public launch.
