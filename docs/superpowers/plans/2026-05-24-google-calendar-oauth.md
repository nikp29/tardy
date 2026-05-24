# Google Calendar OAuth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Google Calendar as a second, OAuth-connected event source alongside macOS Calendar (EventKit), merging and de-duplicating events, with richer structured conference data.

**Architecture:** Refactor today's `CalendarService` into a source-agnostic `EventCoordinator` (owns all timers/notifications) plus pluggable `EventProvider`s (`EventKitProvider`, `GoogleCalendarProvider`). Google auth is delegated to the GoogleSignIn SDK (no-secret Apple OAuth client + PKCE); the Google Calendar REST surface (`calendarList`, `events.list`) is hand-rolled with `URLSession`. The coordinator merges provider outputs via a pure `EventDeduplicator` and notifies `AppDelegate` through the existing delegate contract.

**Tech Stack:** Swift 5.10, AppKit, EventKit, SwiftUI (settings), Swift Testing (`import Testing`), `GoogleSignIn-iOS` (SwiftPM, macOS), `URLSession`.

**Spec:** `docs/superpowers/specs/2026-05-24-google-calendar-oauth-design.md`

---

## File Structure

**New files:**
- `Sources/Tardy/Calendar/EventProvider.swift` — `EventSourceKind` enum, `EventProvider` protocol, `EventCoordinatorDelegate` protocol.
- `Sources/Tardy/Calendar/EventCoordinator.swift` — orchestrator (timers, notifications, merge, notify); refactored from `CalendarService`.
- `Sources/Tardy/Calendar/EventKitProvider.swift` — EventKit fetch/filter/map behind `EventProvider`; extracted from `CalendarService`.
- `Sources/Tardy/Calendar/EventDeduplicator.swift` — pure merge + de-dup.
- `Sources/Tardy/Calendar/Google/HTTPFetching.swift` — `URLSession` seam for tests.
- `Sources/Tardy/Calendar/Google/GoogleAuth.swift` — `GoogleAuthProviding` protocol, `GoogleAuthError`, `GoogleSignInAuthService` impl.
- `Sources/Tardy/Calendar/Google/GoogleCalendarModels.swift` — Codable models for the REST responses.
- `Sources/Tardy/Calendar/Google/GoogleCalendarAPI.swift` — REST client (calendarList, events.list).
- `Sources/Tardy/Calendar/Google/GoogleEventMapper.swift` — pure `GoogleEvent` → `UpcomingEvent`.
- `Sources/Tardy/Calendar/Google/GoogleCalendarProvider.swift` — `EventProvider` impl using auth + API + mapper.
- Tests: `EventDeduplicatorTests.swift`, `GoogleEventMapperTests.swift`, `GoogleCalendarModelsTests.swift`, `GoogleCalendarProviderTests.swift`.

**Modified files:**
- `Sources/Tardy/Models/UpcomingEvent.swift` — add `source`, `iCalUID`.
- `Sources/Tardy/App.swift` — construct `EventCoordinator` with providers; conform to `EventCoordinatorDelegate`.
- `Sources/Tardy/Settings/SettingsManager.swift` — `googleCalendarEnabled` flag.
- `Sources/Tardy/Settings/SettingsView.swift` — "GOOGLE CALENDAR" section.
- `Sources/Tardy/MenuBar/MenuBarController.swift` — pass auth into settings; "Reconnect Google" item; poll-on-open.
- `Package.swift` — add GoogleSignIn dependency.
- `scripts/build-app.sh` — `GIDClientID` + `CFBundleURLTypes` in Info.plist.

**Deleted:**
- `Sources/Tardy/Calendar/CalendarService.swift` — split into `EventCoordinator` + `EventKitProvider`.

---

## Phase 1 — Multi-source refactor (no behavior change)

After Phase 1, Tardy still runs EventKit-only, but through the new pluggable architecture, with all tests green. This phase is independently shippable.

### Task 1: Add `source` and `iCalUID` to `UpcomingEvent`

**Files:**
- Modify: `Sources/Tardy/Models/UpcomingEvent.swift`
- Test: `Tests/TardyTests/UpcomingEventTests.swift`

- [ ] **Step 1: Write the failing test** — append to `UpcomingEventTests.swift`:

```swift
@Test("source defaults to eventKit and iCalUID defaults to nil")
func sourceAndICalUIDDefaults() {
    let e = UpcomingEvent(
        id: "e1", title: "T",
        startDate: Date(), endDate: Date().addingTimeInterval(60),
        location: nil, conferenceURL: nil, phoneNumber: nil, notes: nil
    )
    #expect(e.source == .eventKit)
    #expect(e.iCalUID == nil)
}

@Test("source and iCalUID are stored when provided")
func sourceAndICalUIDStored() {
    let e = UpcomingEvent(
        id: "e1", title: "T",
        startDate: Date(), endDate: Date().addingTimeInterval(60),
        location: nil, conferenceURL: nil, phoneNumber: nil, notes: nil,
        source: .google, iCalUID: "abc@google.com"
    )
    #expect(e.source == .google)
    #expect(e.iCalUID == "abc@google.com")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter UpcomingEvent`
Expected: FAIL — `source`/`iCalUID` and the extra init params don't exist.

- [ ] **Step 3: Modify `UpcomingEvent.swift`** — add the enum, fields, and an explicit init with defaults (so existing call sites keep compiling):

```swift
import Foundation

enum EventSourceKind: String, Equatable, Hashable {
    case eventKit
    case google
}

struct UpcomingEvent: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let location: String?
    let conferenceURL: URL?
    let phoneNumber: String?
    let notes: String?
    let source: EventSourceKind
    let iCalUID: String?

    init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        location: String?,
        conferenceURL: URL?,
        phoneNumber: String?,
        notes: String?,
        source: EventSourceKind = .eventKit,
        iCalUID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.location = location
        self.conferenceURL = conferenceURL
        self.phoneNumber = phoneNumber
        self.notes = notes
        self.source = source
        self.iCalUID = iCalUID
    }

    static func == (lhs: UpcomingEvent, rhs: UpcomingEvent) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    func hasChanged(comparedTo other: UpcomingEvent) -> Bool {
        title != other.title ||
        startDate != other.startDate ||
        endDate != other.endDate ||
        location != other.location ||
        conferenceURL != other.conferenceURL ||
        phoneNumber != other.phoneNumber ||
        notes != other.notes
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter UpcomingEvent`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Tardy/Models/UpcomingEvent.swift Tests/TardyTests/UpcomingEventTests.swift
git commit -m "feat: add source and iCalUID to UpcomingEvent"
```

### Task 2: Define `EventProvider` protocol and coordinator delegate

**Files:**
- Create: `Sources/Tardy/Calendar/EventProvider.swift`

- [ ] **Step 1: Create the file**

```swift
import Foundation

/// A source of calendar events (EventKit, Google, …).
protocol EventProvider: AnyObject {
    var kind: EventSourceKind { get }
    /// Whether this provider should currently contribute events.
    var isEnabled: Bool { get }
    /// Called by the provider when its underlying data changes and the
    /// coordinator should re-poll immediately (e.g. EventKit store changed).
    var onChange: (() -> Void)? { get set }
    /// Begin observing changes / acquiring access. Idempotent.
    func start()
    /// Fetch events overlapping [start, end].
    func fetchEvents(start: Date, end: Date) async -> [UpcomingEvent]
}

protocol EventCoordinatorDelegate: AnyObject {
    func eventCoordinator(
        _ coordinator: EventCoordinator,
        didUpdateEvents events: [UpcomingEvent],
        forceReschedule: Bool
    )
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: FAIL — `EventCoordinator` not defined yet (referenced in delegate). This is expected; Task 4 defines it. If you prefer a green build here, temporarily comment the delegate protocol and add it in Task 4. Otherwise proceed to Task 3–4 and build at the end of Task 4.

- [ ] **Step 3: Commit**

```bash
git add Sources/Tardy/Calendar/EventProvider.swift
git commit -m "feat: add EventProvider protocol and coordinator delegate"
```

### Task 3: Extract `EventKitProvider` from `CalendarService`

**Files:**
- Create: `Sources/Tardy/Calendar/EventKitProvider.swift`

This moves the EventKit fetch/filter/map logic out of `CalendarService` verbatim, adapting it to `EventProvider`. The change-observation (`EKEventStoreChanged`) calls `onChange`; the timer/wake/timezone orchestration stays in the coordinator (Task 4).

- [ ] **Step 1: Create the file**

```swift
import AppKit
import EventKit
import Foundation

final class EventKitProvider: EventProvider {
    let kind: EventSourceKind = .eventKit
    var isEnabled: Bool { true } // EventKit is always available as a source
    var onChange: (() -> Void)?

    private let store = EKEventStore()
    private var accessGranted = false

    func start() {
        requestAccess { [weak self] granted in
            guard let self else { return }
            self.accessGranted = granted
            if !granted { print("Tardy: Calendar access denied") }
            NotificationCenter.default.addObserver(
                self, selector: #selector(self.storeChanged),
                name: .EKEventStoreChanged, object: self.store
            )
            self.onChange?()
        }
    }

    @objc private func storeChanged(_ note: Notification) {
        onChange?()
    }

    func fetchEvents(start: Date, end: Date) async -> [UpcomingEvent] {
        guard accessGranted else { return [] }
        store.refreshSourcesIfNecessary()
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let ekEvents = store.events(matching: predicate)

        let filtered = ekEvents.filter { event in
            if event.isAllDay { return false }
            if event.status == .canceled { return false }
            if let me = event.attendees?.first(where: { $0.isCurrentUser }),
               me.participantStatus == .declined { return false }
            return true
        }

        return filtered.map { event in
            let conferenceInfo = ConferenceLinkExtractor.extract(
                url: event.url, notes: event.notes, location: event.location
            )
            var conferenceURL: URL?
            var phoneNumber: String?
            var notes: String?
            switch conferenceInfo {
            case .videoCall(let url, _): conferenceURL = url
            case .phone(let number): phoneNumber = number
            case .notes(let text): notes = text
            case nil: break
            }
            return UpcomingEvent(
                id: event.eventIdentifier,
                title: event.title ?? "Untitled Event",
                startDate: event.startDate,
                endDate: event.endDate,
                location: event.location,
                conferenceURL: conferenceURL,
                phoneNumber: phoneNumber,
                notes: notes,
                source: .eventKit,
                iCalUID: event.calendarItemExternalIdentifier
            )
        }
    }

    private func requestAccess(completion: @escaping (Bool) -> Void) {
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { granted, _ in
                DispatchQueue.main.async { completion(granted) }
            }
        } else {
            store.requestAccess(to: .event) { granted, _ in
                DispatchQueue.main.async { completion(granted) }
            }
        }
    }
}
```

- [ ] **Step 2: Commit** (build happens at end of Task 4)

```bash
git add Sources/Tardy/Calendar/EventKitProvider.swift
git commit -m "feat: extract EventKitProvider from CalendarService"
```

### Task 4: Create `EventCoordinator` and delete `CalendarService`

**Files:**
- Create: `Sources/Tardy/Calendar/EventCoordinator.swift`
- Delete: `Sources/Tardy/Calendar/CalendarService.swift`

The coordinator owns the timer/notification orchestration previously in `CalendarService` (poll = 300s, midnight rollover, wake, timezone, day-change) and the 26h window constant, and now fans out to providers + merges. Merge is delegated to `EventDeduplicator` (Task 5); for this task use a temporary trivial merge (concatenate) so the build is green, then Task 5 replaces it.

- [ ] **Step 1: Create the file**

```swift
import AppKit
import Foundation

final class EventCoordinator {
    /// Rolling fetch window. See spec/CalendarService notes: 26h covers the
    /// midnight boundary and delayed rollovers.
    static let fetchWindowSeconds: TimeInterval = 26 * 3600

    private let providers: [EventProvider]
    private var pollTimer: Timer?
    private var midnightTimer: Timer?

    weak var delegate: EventCoordinatorDelegate?

    init(providers: [EventProvider]) {
        self.providers = providers
        for p in providers {
            p.onChange = { [weak self] in self?.refresh() }
        }
    }

    func start() {
        providers.forEach { $0.start() }
        subscribeToSystemNotifications()
        startPolling()
        scheduleMidnightRollover()
        refresh()
    }

    func stop() {
        pollTimer?.invalidate(); pollTimer = nil
        midnightTimer?.invalidate(); midnightTimer = nil
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// Public entry point used by poll-on-open (Phase 7).
    func refresh(forceReschedule: Bool = false) {
        let now = Date()
        let end = now.addingTimeInterval(Self.fetchWindowSeconds)
        Task { [weak self] in
            guard let self else { return }
            var groups: [[UpcomingEvent]] = []
            for provider in self.providers where provider.isEnabled {
                groups.append(await provider.fetchEvents(start: now, end: end))
            }
            let merged = EventDeduplicator.merge(groups)
            await MainActor.run {
                self.delegate?.eventCoordinator(self, didUpdateEvents: merged, forceReschedule: forceReschedule)
            }
        }
    }

    // MARK: - System notifications

    private func subscribeToSystemNotifications() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(timezoneOrDayChanged), name: .NSSystemTimeZoneDidChange, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(timezoneOrDayChanged), name: .NSCalendarDayChanged, object: nil)
    }

    @objc private func didWake(_ n: Notification) { refresh(forceReschedule: true) }

    @objc private func timezoneOrDayChanged(_ n: Notification) {
        midnightTimer?.invalidate(); midnightTimer = nil
        scheduleMidnightRollover()
        refresh(forceReschedule: true)
    }

    // MARK: - Timers

    private func startPolling() {
        let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func scheduleMidnightRollover() {
        let cal = Calendar.current
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()),
              let midnight = cal.dateInterval(of: .day, for: tomorrow)?.start else { return }
        let interval = max(1, midnight.timeIntervalSinceNow)
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            self?.refresh(forceReschedule: true)
            self?.scheduleMidnightRollover()
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        midnightTimer = timer
    }
}
```

- [ ] **Step 2: Add temporary merge** — create `EventDeduplicator.swift` with a placeholder so the build is green now; Task 5 fills it in with tests:

```swift
import Foundation

enum EventDeduplicator {
    static func merge(_ groups: [[UpcomingEvent]]) -> [UpcomingEvent] {
        groups.flatMap { $0 } // replaced in Task 5
    }
}
```

- [ ] **Step 3: Delete `CalendarService.swift`**

Run: `git rm Sources/Tardy/Calendar/CalendarService.swift`

- [ ] **Step 4: Update `App.swift`** — replace the `CalendarService` wiring with `EventCoordinator`. Change the stored property and delegate conformance:

Replace lines `Sources/Tardy/App.swift:8` (`private var calendarService: CalendarService!`) with:
```swift
    private var eventCoordinator: EventCoordinator!
```

Replace the `class AppDelegate ... CalendarServiceDelegate` declaration (`Sources/Tardy/App.swift:5`) with:
```swift
class AppDelegate: NSObject, NSApplicationDelegate, EventCoordinatorDelegate {
```

Replace the construction block (`Sources/Tardy/App.swift:26-28`):
```swift
        calendarService = CalendarService()
        calendarService.delegate = self
        calendarService.start()
```
with:
```swift
        eventCoordinator = EventCoordinator(providers: [EventKitProvider()])
        eventCoordinator.delegate = self
        eventCoordinator.start()
```

Replace the delegate method (`Sources/Tardy/App.swift:38-52`):
```swift
    func calendarService(
        _ service: CalendarService,
        didUpdateEvents events: [UpcomingEvent],
        forceReschedule: Bool
    ) {
```
with:
```swift
    func eventCoordinator(
        _ coordinator: EventCoordinator,
        didUpdateEvents events: [UpcomingEvent],
        forceReschedule: Bool
    ) {
```
(The body — `alertScheduler.updateEvents` + `menuBarController.updateNextEvent` — stays identical.)

- [ ] **Step 5: Build and run full test suite**

Run: `swift build && swift test`
Expected: PASS, builds clean. Behavior is unchanged (EventKit-only through the new architecture).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: replace CalendarService with EventCoordinator + EventKitProvider"
```

### Task 5: Implement `EventDeduplicator` (pure, TDD)

**Files:**
- Modify: `Sources/Tardy/Calendar/EventDeduplicator.swift`
- Test: `Tests/TardyTests/EventDeduplicatorTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import Testing
import Foundation
@testable import Tardy

@Suite("EventDeduplicator")
struct EventDeduplicatorTests {
    private func ev(
        id: String, title: String = "Standup",
        start: Date = Date(timeIntervalSince1970: 1_000_000),
        source: EventSourceKind = .eventKit, iCalUID: String? = nil,
        conferenceURL: URL? = nil
    ) -> UpcomingEvent {
        UpcomingEvent(id: id, title: title, startDate: start,
            endDate: start.addingTimeInterval(1800), location: nil,
            conferenceURL: conferenceURL, phoneNumber: nil, notes: nil,
            source: source, iCalUID: iCalUID)
    }

    @Test("merges disjoint events and sorts by start")
    func mergesDisjoint() {
        let a = ev(id: "a", start: Date(timeIntervalSince1970: 200))
        let b = ev(id: "b", start: Date(timeIntervalSince1970: 100))
        let out = EventDeduplicator.merge([[a], [b]])
        #expect(out.map(\.id) == ["b", "a"])
    }

    @Test("dedupes by matching iCalUID, preferring Google")
    func dedupesByICalUID() {
        let ek = ev(id: "ek", source: .eventKit, iCalUID: "uid-1")
        let g = ev(id: "g", source: .google, iCalUID: "uid-1",
                   conferenceURL: URL(string: "https://meet.google.com/xyz"))
        let out = EventDeduplicator.merge([[ek], [g]])
        #expect(out.count == 1)
        #expect(out.first?.source == .google)
        #expect(out.first?.conferenceURL?.absoluteString == "https://meet.google.com/xyz")
    }

    @Test("dedupes by (start, normalized title) when no iCalUID")
    func dedupesByStartTitle() {
        let start = Date(timeIntervalSince1970: 500)
        let ek = ev(id: "ek", title: "Team Sync ", start: start, source: .eventKit)
        let g = ev(id: "g", title: "team sync", start: start, source: .google)
        let out = EventDeduplicator.merge([[ek], [g]])
        #expect(out.count == 1)
        #expect(out.first?.source == .google)
    }

    @Test("does not dedupe different events at same time")
    func keepsDistinct() {
        let start = Date(timeIntervalSince1970: 500)
        let a = ev(id: "a", title: "Sync", start: start)
        let b = ev(id: "b", title: "1:1", start: start)
        let out = EventDeduplicator.merge([[a], [b]])
        #expect(out.count == 2)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter EventDeduplicator`
Expected: FAIL — placeholder merge doesn't dedupe.

- [ ] **Step 3: Implement**

```swift
import Foundation

enum EventDeduplicator {
    /// Merge events from multiple providers, removing duplicates that represent
    /// the same meeting. When duplicates are found, prefer the Google copy
    /// (richer structured conference data). Result is sorted by start date.
    static func merge(_ groups: [[UpcomingEvent]]) -> [UpcomingEvent] {
        var byKey: [String: UpcomingEvent] = [:]
        var order: [String] = []

        for event in groups.flatMap({ $0 }) {
            let key = dedupKey(for: event)
            if let existing = byKey[key] {
                byKey[key] = prefer(existing, event)
            } else {
                byKey[key] = event
                order.append(key)
            }
        }

        return order.compactMap { byKey[$0] }
            .sorted { $0.startDate < $1.startDate }
    }

    private static func dedupKey(for e: UpcomingEvent) -> String {
        if let uid = e.iCalUID, !uid.isEmpty { return "uid:\(uid)" }
        let title = e.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "st:\(e.startDate.timeIntervalSince1970):\(title)"
    }

    private static func prefer(_ a: UpcomingEvent, _ b: UpcomingEvent) -> UpcomingEvent {
        if a.source == .google { return a }
        if b.source == .google { return b }
        return a
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter EventDeduplicator`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Tardy/Calendar/EventDeduplicator.swift Tests/TardyTests/EventDeduplicatorTests.swift
git commit -m "feat: implement EventDeduplicator merge + dedup"
```

---

## Phase 2 — Google Cloud project & OAuth client

No app code; this provisions credentials and wires the URL scheme. `gcloud` requires the Python override noted in the spec.

### Task 6: Enable Calendar API and create the OAuth client

- [ ] **Step 1: Point gcloud at a working Python and confirm project**

```bash
export CLOUDSDK_PYTHON="$(command -v python3.14)"
~/google-cloud-sdk/bin/gcloud config get-value project
```
Expected: `my-project-1564602150265` (or set a dedicated project with `gcloud config set project <id>`).

- [ ] **Step 2: Enable the Google Calendar API**

```bash
export CLOUDSDK_PYTHON="$(command -v python3.14)"
~/google-cloud-sdk/bin/gcloud services enable calendar-json.googleapis.com
```
Expected: `Operation ... finished successfully.`

- [ ] **Step 3: Configure the OAuth consent screen (Google Auth Platform, Console)**

In the Cloud Console → APIs & Services → OAuth consent screen:
- User type: **External**, publishing status: **Testing**.
- App name: `Tardy`; support email + developer contact: `nikp29@gmail.com`.
- Add scope: `https://www.googleapis.com/auth/calendar.readonly`.
- Add `nikp29@gmail.com` (and any beta testers) under **Test users**.

(Consent-screen config is not reliably scriptable via `gcloud` for consumer apps; do this in the Console.)

- [ ] **Step 4: Create the Apple-platform OAuth client (Console)**

APIs & Services → Credentials → Create credentials → OAuth client ID → Application type **iOS** (Apple platforms):
- Bundle ID: `com.nikp29.tardy`.
- Record the **Client ID** (form `NNN-xxxx.apps.googleusercontent.com`). There is **no client secret** for this type.
- The redirect custom scheme is the reverse of the client ID: `com.googleusercontent.apps.NNN-xxxx`.

- [ ] **Step 5: Record the client ID for the build**

Create `Sources/Tardy/Calendar/Google/GoogleOAuthConfig.swift`:

```swift
import Foundation

/// Public OAuth client ID for the Apple-platform client. Not a secret:
/// it appears in the consent URL and is safe to ship (PKCE secures the flow).
enum GoogleOAuthConfig {
    static let clientID = "NNN-xxxx.apps.googleusercontent.com" // from Task 6, Step 4
    static let scopes = ["https://www.googleapis.com/auth/calendar.readonly"]
    /// Reverse-client-ID URL scheme used as the OAuth redirect.
    static var redirectScheme: String {
        "com.googleusercontent.apps." + clientID
            .replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
    }
}
```

- [ ] **Step 6: Commit**

```bash
git add Sources/Tardy/Calendar/Google/GoogleOAuthConfig.swift
git commit -m "chore: add Google OAuth client config (public client ID)"
```

### Task 7: Register the redirect URL scheme in the app bundle

**Files:**
- Modify: `scripts/build-app.sh`

- [ ] **Step 1: Add `GIDClientID` and `CFBundleURLTypes` to the Info.plist heredoc**

In `scripts/build-app.sh`, inside the `<dict>` of the Info.plist (before the closing `</dict>` at `scripts/build-app.sh:75`), insert:

```xml
    <key>GIDClientID</key>
    <string>NNN-xxxx.apps.googleusercontent.com</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>com.googleusercontent.apps.NNN-xxxx</string>
            </array>
        </dict>
    </array>
```
(Use the real client ID / reverse scheme from Task 6.)

- [ ] **Step 2: Rebuild and confirm the plist contains the scheme**

```bash
./scripts/build-app.sh 0.2.0-dev
/usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes:0:CFBundleURLSchemes:0" .build/app/Tardy.app/Contents/Info.plist
```
Expected: prints `com.googleusercontent.apps.NNN-xxxx`.

- [ ] **Step 3: Commit**

```bash
git add scripts/build-app.sh
git commit -m "build: register Google OAuth redirect scheme + GIDClientID in Info.plist"
```

---

## Phase 3 — Google authentication

### Task 8: Add the GoogleSignIn dependency

**Files:**
- Modify: `Package.swift`

- [ ] **Step 1: Add the package + product**

Replace the `dependencies:`/`targets:` of `Package.swift` so the executable target depends on GoogleSignIn:

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Tardy",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/google/GoogleSignIn-iOS.git", from: "8.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Tardy",
            dependencies: [
                .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS")
            ],
            path: "Sources/Tardy",
            exclude: ["Resources/Tardy.entitlements"],
            resources: [
                .copy("Resources/CalendarUsage.plist"),
                .copy("Resources/Fonts"),
                .copy("Resources/Sounds"),
            ]
        ),
        .testTarget(
            name: "TardyTests",
            dependencies: ["Tardy"],
            path: "Tests/TardyTests"
        ),
    ]
)
```

- [ ] **Step 2: Resolve and build**

Run: `swift package resolve && swift build`
Expected: GoogleSignIn (and its deps: AppAuth, GTMAppAuth, GTMSessionFetcher) resolve; build succeeds. If the resolved major version differs from 8.x, note the actual version — Task 9's API calls (`signIn(withPresenting:)`, `refreshTokensIfNeeded`) match GoogleSignIn 7/8; adjust if the installed version's signatures differ.

- [ ] **Step 3: Commit**

```bash
git add Package.swift Package.resolved
git commit -m "build: add GoogleSignIn-iOS dependency"
```

### Task 9: Implement `GoogleAuthProviding` + GoogleSignIn wrapper

**Files:**
- Create: `Sources/Tardy/Calendar/Google/GoogleAuth.swift`

- [ ] **Step 1: Create the file**

```swift
import AppKit
import Foundation
import GoogleSignIn

enum GoogleAuthError: Error, Equatable {
    case needsReauth
    case cancelled
    case notConfigured
}

/// Abstraction over Google auth so providers and tests don't depend on the SDK.
protocol GoogleAuthProviding: AnyObject {
    var isSignedIn: Bool { get }
    var accountEmail: String? { get }
    /// Restore a prior session at launch (no UI). Safe to call when signed out.
    func restorePreviousSignIn() async
    /// Interactive sign-in. `anchor` is the presenting window for the consent UI.
    func signIn(presenting anchor: NSWindow) async throws
    /// A currently-valid access token, refreshing if needed.
    /// Throws `.needsReauth` if the session can't be refreshed.
    func validAccessToken() async throws -> String
    func signOut()
}

final class GoogleSignInAuthService: GoogleAuthProviding {
    static let shared = GoogleSignInAuthService()

    private var signIn: GIDSignIn { GIDSignIn.sharedInstance }

    init() {
        signIn.configuration = GIDConfiguration(clientID: GoogleOAuthConfig.clientID)
    }

    var isSignedIn: Bool { signIn.currentUser != nil }
    var accountEmail: String? { signIn.currentUser?.profile?.email }

    func restorePreviousSignIn() async {
        guard signIn.hasPreviousSignIn() else { return }
        _ = try? await signIn.restorePreviousSignIn()
    }

    func signIn(presenting anchor: NSWindow) async throws {
        do {
            try await signIn.signIn(
                withPresenting: anchor,
                hint: nil,
                additionalScopes: GoogleOAuthConfig.scopes
            )
        } catch {
            if (error as NSError).code == GIDSignInError.canceled.rawValue {
                throw GoogleAuthError.cancelled
            }
            throw error
        }
    }

    func validAccessToken() async throws -> String {
        guard let user = signIn.currentUser else { throw GoogleAuthError.needsReauth }
        do {
            let refreshed = try await user.refreshTokensIfNeeded()
            return refreshed.accessToken.tokenString
        } catch {
            throw GoogleAuthError.needsReauth
        }
    }

    func signOut() {
        signIn.signOut()
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: PASS. (If GoogleSignIn's installed API differs — e.g. `refreshTokensIfNeeded` returns `GIDGoogleUser` vs a token — adjust the two token-access lines accordingly; the protocol surface stays the same.)

- [ ] **Step 3: Commit**

```bash
git add Sources/Tardy/Calendar/Google/GoogleAuth.swift
git commit -m "feat: add GoogleAuthProviding protocol + GoogleSignIn wrapper"
```

---

## Phase 4 — Google Calendar REST: models, mapping, client

### Task 10: Codable models (TDD against a real fixture)

**Files:**
- Create: `Sources/Tardy/Calendar/Google/GoogleCalendarModels.swift`
- Test: `Tests/TardyTests/GoogleCalendarModelsTests.swift`

- [ ] **Step 1: Capture a real events.list payload with `gws` (reference for field shapes)**

```bash
gws calendar events list --params '{"calendarId":"primary","maxResults":5,"singleEvents":true,"orderBy":"startTime"}' --format json | head -120
```
Use the output to confirm field names (`iCalUID`, `start.dateTime` vs `start.date`, `conferenceData.entryPoints[].entryPointType`, `attendees[].self`, `attendees[].responseStatus`, `hangoutLink`, `status`).

- [ ] **Step 2: Write failing decode tests**

```swift
import Testing
import Foundation
@testable import Tardy

@Suite("GoogleCalendarModels")
struct GoogleCalendarModelsTests {
    @Test("decodes a timed event with conferenceData and attendees")
    func decodesTimedEvent() throws {
        let json = """
        {
          "items": [{
            "id": "evt1",
            "iCalUID": "uid-1@google.com",
            "status": "confirmed",
            "summary": "Standup",
            "location": "HQ",
            "description": "notes here",
            "hangoutLink": "https://meet.google.com/abc-defg-hij",
            "start": {"dateTime": "2026-05-25T10:00:00-04:00"},
            "end": {"dateTime": "2026-05-25T10:30:00-04:00"},
            "conferenceData": {"entryPoints": [
              {"entryPointType": "video", "uri": "https://meet.google.com/abc-defg-hij"},
              {"entryPointType": "phone", "uri": "tel:+1-555-555-5555", "label": "+1 555-555-5555"}
            ]},
            "attendees": [{"self": true, "responseStatus": "accepted"}]
          }],
          "nextSyncToken": "TOKEN123"
        }
        """.data(using: .utf8)!
        let resp = try GoogleCalendarModels.decoder.decode(GoogleEventsResponse.self, from: json)
        #expect(resp.nextSyncToken == "TOKEN123")
        let e = try #require(resp.items.first)
        #expect(e.iCalUID == "uid-1@google.com")
        #expect(e.start.dateTime != nil)
        #expect(e.start.date == nil)
        #expect(e.conferenceData?.entryPoints?.first?.entryPointType == "video")
        #expect(e.attendees?.first?.selfAttendee == true)
    }

    @Test("decodes an all-day event (date, no dateTime)")
    func decodesAllDay() throws {
        let json = """
        {"items":[{"id":"d1","status":"confirmed","summary":"Holiday",
          "start":{"date":"2026-05-25"},"end":{"date":"2026-05-26"}}]}
        """.data(using: .utf8)!
        let resp = try GoogleCalendarModels.decoder.decode(GoogleEventsResponse.self, from: json)
        let e = try #require(resp.items.first)
        #expect(e.start.dateTime == nil)
        #expect(e.start.date == "2026-05-25")
    }

    @Test("decodes calendar list")
    func decodesCalendarList() throws {
        let json = """
        {"items":[{"id":"primary"},{"id":"team@group.calendar.google.com"}]}
        """.data(using: .utf8)!
        let resp = try GoogleCalendarModels.decoder.decode(GoogleCalendarListResponse.self, from: json)
        #expect(resp.items.map(\.id) == ["primary", "team@group.calendar.google.com"])
    }
}
```

- [ ] **Step 3: Run to verify failure**

Run: `swift test --filter GoogleCalendarModels`
Expected: FAIL — types undefined.

- [ ] **Step 4: Implement the models**

```swift
import Foundation

enum GoogleCalendarModels {
    /// RFC3339 decoder. Google returns `dateTime` like 2026-05-25T10:00:00-04:00.
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        let fmtFractional = ISO8601DateFormatter()
        fmtFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = fmt.date(from: s) ?? fmtFractional.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Bad RFC3339 date: \(s)"))
        }
        return d
    }()
}

struct GoogleCalendarListResponse: Decodable {
    let items: [GoogleCalendarListEntry]
}
struct GoogleCalendarListEntry: Decodable {
    let id: String
}

struct GoogleEventsResponse: Decodable {
    let items: [GoogleEvent]
    let nextSyncToken: String?
    let nextPageToken: String?
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([GoogleEvent].self, forKey: .items) ?? []
        nextSyncToken = try c.decodeIfPresent(String.self, forKey: .nextSyncToken)
        nextPageToken = try c.decodeIfPresent(String.self, forKey: .nextPageToken)
    }
    enum CodingKeys: String, CodingKey { case items, nextSyncToken, nextPageToken }
}

struct GoogleEvent: Decodable {
    let id: String
    let iCalUID: String?
    let status: String?
    let summary: String?
    let location: String?
    let description: String?
    let hangoutLink: String?
    let start: GoogleEventDateTime
    let end: GoogleEventDateTime
    let conferenceData: GoogleConferenceData?
    let attendees: [GoogleAttendee]?
}

struct GoogleEventDateTime: Decodable {
    let dateTime: Date?
    let date: String?    // all-day events use this instead of dateTime
}

struct GoogleConferenceData: Decodable {
    let entryPoints: [GoogleEntryPoint]?
}
struct GoogleEntryPoint: Decodable {
    let entryPointType: String?   // "video", "phone", "more", "sip"
    let uri: String?
    let label: String?
}

struct GoogleAttendee: Decodable {
    let selfAttendee: Bool?
    let responseStatus: String?    // "needsAction", "declined", "tentative", "accepted"
    enum CodingKeys: String, CodingKey {
        case selfAttendee = "self"
        case responseStatus
    }
}
```

- [ ] **Step 5: Run to verify pass**

Run: `swift test --filter GoogleCalendarModels`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/Tardy/Calendar/Google/GoogleCalendarModels.swift Tests/TardyTests/GoogleCalendarModelsTests.swift
git commit -m "feat: add Google Calendar Codable models with decode tests"
```

### Task 11: Implement `GoogleEventMapper` (pure, TDD)

**Files:**
- Create: `Sources/Tardy/Calendar/Google/GoogleEventMapper.swift`
- Test: `Tests/TardyTests/GoogleEventMapperTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import Testing
import Foundation
@testable import Tardy

@Suite("GoogleEventMapper")
struct GoogleEventMapperTests {
    private func decode(_ json: String) throws -> GoogleEvent {
        let wrapped = "{\"items\":[\(json)]}".data(using: .utf8)!
        return try GoogleCalendarModels.decoder.decode(GoogleEventsResponse.self, from: wrapped).items[0]
    }

    @Test("maps a timed event and prefers video entryPoint for conference URL")
    func mapsTimedEvent() throws {
        let e = try decode("""
        {"id":"e1","iCalUID":"uid-1","status":"confirmed","summary":"Standup",
         "start":{"dateTime":"2026-05-25T10:00:00Z"},"end":{"dateTime":"2026-05-25T10:30:00Z"},
         "hangoutLink":"https://meet.google.com/zzz",
         "conferenceData":{"entryPoints":[{"entryPointType":"video","uri":"https://meet.google.com/abc"}]}}
        """)
        let m = try #require(GoogleEventMapper.map(e))
        #expect(m.id == "e1")
        #expect(m.title == "Standup")
        #expect(m.source == .google)
        #expect(m.iCalUID == "uid-1")
        #expect(m.conferenceURL?.absoluteString == "https://meet.google.com/abc")
    }

    @Test("falls back to hangoutLink when no video entryPoint")
    func fallsBackToHangoutLink() throws {
        let e = try decode("""
        {"id":"e2","status":"confirmed","summary":"Sync",
         "start":{"dateTime":"2026-05-25T10:00:00Z"},"end":{"dateTime":"2026-05-25T10:30:00Z"},
         "hangoutLink":"https://meet.google.com/zzz"}
        """)
        let m = try #require(GoogleEventMapper.map(e))
        #expect(m.conferenceURL?.absoluteString == "https://meet.google.com/zzz")
    }

    @Test("extracts phone entryPoint when no video")
    func extractsPhone() throws {
        let e = try decode("""
        {"id":"e3","status":"confirmed","summary":"Call",
         "start":{"dateTime":"2026-05-25T10:00:00Z"},"end":{"dateTime":"2026-05-25T10:30:00Z"},
         "conferenceData":{"entryPoints":[{"entryPointType":"phone","uri":"tel:+15555555555","label":"+1 555-555-5555"}]}}
        """)
        let m = try #require(GoogleEventMapper.map(e))
        #expect(m.conferenceURL == nil)
        #expect(m.phoneNumber == "+1 555-555-5555")
    }

    @Test("returns nil for all-day, cancelled, and declined events")
    func filtersOut() throws {
        let allDay = try decode("""
        {"id":"a","status":"confirmed","summary":"Holiday","start":{"date":"2026-05-25"},"end":{"date":"2026-05-26"}}
        """)
        let cancelled = try decode("""
        {"id":"c","status":"cancelled","summary":"X","start":{"dateTime":"2026-05-25T10:00:00Z"},"end":{"dateTime":"2026-05-25T10:30:00Z"}}
        """)
        let declined = try decode("""
        {"id":"d","status":"confirmed","summary":"Y","start":{"dateTime":"2026-05-25T10:00:00Z"},"end":{"dateTime":"2026-05-25T10:30:00Z"},
         "attendees":[{"self":true,"responseStatus":"declined"}]}
        """)
        #expect(GoogleEventMapper.map(allDay) == nil)
        #expect(GoogleEventMapper.map(cancelled) == nil)
        #expect(GoogleEventMapper.map(declined) == nil)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter GoogleEventMapper`
Expected: FAIL — `GoogleEventMapper` undefined.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Maps a Google Calendar API event into Tardy's domain model, applying the
/// same filtering rules as EventKit (skip all-day / cancelled / declined).
enum GoogleEventMapper {
    static func map(_ e: GoogleEvent) -> UpcomingEvent? {
        // All-day events use `date` instead of `dateTime`.
        guard let start = e.start.dateTime, let end = e.end.dateTime else { return nil }
        if e.status == "cancelled" { return nil }
        if let me = e.attendees?.first(where: { $0.selfAttendee == true }),
           me.responseStatus == "declined" { return nil }

        let video = e.conferenceData?.entryPoints?.first { $0.entryPointType == "video" }
        let phone = e.conferenceData?.entryPoints?.first { $0.entryPointType == "phone" }

        var conferenceURL: URL?
        if let uri = video?.uri { conferenceURL = URL(string: uri) }
        if conferenceURL == nil, let h = e.hangoutLink { conferenceURL = URL(string: h) }

        var phoneNumber: String?
        var notes: String?
        if conferenceURL == nil {
            if let p = phone { phoneNumber = p.label ?? p.uri }
            else {
                // Fall back to scraping description/location like EventKit.
                switch ConferenceLinkExtractor.extract(url: nil, notes: e.description, location: e.location) {
                case .videoCall(let url, _): conferenceURL = url
                case .phone(let number): phoneNumber = number
                case .notes(let text): notes = text
                case nil: break
                }
            }
        }

        return UpcomingEvent(
            id: e.id,
            title: e.summary ?? "Untitled Event",
            startDate: start,
            endDate: end,
            location: e.location,
            conferenceURL: conferenceURL,
            phoneNumber: phoneNumber,
            notes: notes,
            source: .google,
            iCalUID: e.iCalUID
        )
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter GoogleEventMapper`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Tardy/Calendar/Google/GoogleEventMapper.swift Tests/TardyTests/GoogleEventMapperTests.swift
git commit -m "feat: implement GoogleEventMapper with filtering + conference extraction"
```

### Task 12: HTTP seam + `GoogleCalendarAPI` client

**Files:**
- Create: `Sources/Tardy/Calendar/Google/HTTPFetching.swift`
- Create: `Sources/Tardy/Calendar/Google/GoogleCalendarAPI.swift`

- [ ] **Step 1: Create the HTTP seam**

```swift
import Foundation

/// Minimal seam over URLSession so tests can inject canned responses.
protocol HTTPFetching {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPFetching {}
```

- [ ] **Step 2: Create the API client**

```swift
import Foundation

enum GoogleCalendarAPIError: Error, Equatable {
    case unauthorized          // 401 — caller should re-auth
    case http(Int)
    case syncTokenExpired      // 410 — caller should drop syncToken and full-resync
}

/// Thin REST client for the Calendar API. Auth and HTTP are injected.
final class GoogleCalendarAPI {
    private let auth: GoogleAuthProviding
    private let http: HTTPFetching
    private let base = URL(string: "https://www.googleapis.com/calendar/v3/")!

    init(auth: GoogleAuthProviding, http: HTTPFetching = URLSession.shared) {
        self.auth = auth
        self.http = http
    }

    func calendarIDs() async throws -> [String] {
        let url = base.appendingPathComponent("users/me/calendarList")
        let data = try await get(url)
        return try GoogleCalendarModels.decoder
            .decode(GoogleCalendarListResponse.self, from: data)
            .items.map(\.id)
    }

    /// Fetch events for one calendar within [start, end]. If `syncToken` is set,
    /// performs an incremental sync instead (timeMin/timeMax omitted, per API rules).
    func events(calendarID: String, start: Date, end: Date, syncToken: String?) async throws -> GoogleEventsResponse {
        var comps = URLComponents(
            url: base.appendingPathComponent("calendars/\(calendarID)/events"),
            resolvingAgainstBaseURL: false)!
        var q = [
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "maxResults", value: "250"),
        ]
        if let syncToken {
            q.append(URLQueryItem(name: "syncToken", value: syncToken))
        } else {
            let iso = ISO8601DateFormatter()
            q.append(URLQueryItem(name: "timeMin", value: iso.string(from: start)))
            q.append(URLQueryItem(name: "timeMax", value: iso.string(from: end)))
            q.append(URLQueryItem(name: "orderBy", value: "startTime"))
        }
        comps.queryItems = q
        let data = try await get(comps.url!)
        return try GoogleCalendarModels.decoder.decode(GoogleEventsResponse.self, from: data)
    }

    private func get(_ url: URL) async throws -> Data {
        let token = try await auth.validAccessToken()
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await http.data(for: req)
        guard let code = (response as? HTTPURLResponse)?.statusCode else { return data }
        switch code {
        case 200...299: return data
        case 401:       throw GoogleCalendarAPIError.unauthorized
        case 410:       throw GoogleCalendarAPIError.syncTokenExpired
        default:        throw GoogleCalendarAPIError.http(code)
        }
    }
}
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Sources/Tardy/Calendar/Google/HTTPFetching.swift Sources/Tardy/Calendar/Google/GoogleCalendarAPI.swift
git commit -m "feat: add HTTP seam and GoogleCalendarAPI REST client"
```

---

## Phase 5 — GoogleCalendarProvider + wiring

### Task 13: Implement `GoogleCalendarProvider` (TDD with fakes)

**Files:**
- Create: `Sources/Tardy/Calendar/Google/GoogleCalendarProvider.swift`
- Test: `Tests/TardyTests/GoogleCalendarProviderTests.swift`

- [ ] **Step 1: Write failing tests with fake auth + HTTP**

```swift
import Testing
import Foundation
@testable import Tardy

final class FakeAuth: GoogleAuthProviding {
    var signedIn: Bool
    init(signedIn: Bool) { self.signedIn = signedIn }
    var isSignedIn: Bool { signedIn }
    var accountEmail: String? { signedIn ? "me@gmail.com" : nil }
    func restorePreviousSignIn() async {}
    func signIn(presenting anchor: NSWindow) async throws {}
    func validAccessToken() async throws -> String {
        if signedIn { return "token" }
        throw GoogleAuthError.needsReauth
    }
    func signOut() { signedIn = false }
}

struct StubHTTP: HTTPFetching {
    let routes: [(match: (URL) -> Bool, body: String)]
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url!
        let body = routes.first { $0.match(url) }?.body ?? "{}"
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (body.data(using: .utf8)!, resp)
    }
}

@Suite("GoogleCalendarProvider")
struct GoogleCalendarProviderTests {
    @Test("returns empty and is disabled when signed out")
    func emptyWhenSignedOut() async {
        let provider = GoogleCalendarProvider(auth: FakeAuth(signedIn: false), http: StubHTTP(routes: []))
        provider.setEnabled(true)
        #expect(provider.isEnabled == false) // gated on sign-in
        let out = await provider.fetchEvents(start: Date(), end: Date().addingTimeInterval(3600))
        #expect(out.isEmpty)
    }

    @Test("fetches, maps, and filters events across calendars")
    func fetchesAndMaps() async {
        let calList = #"{"items":[{"id":"primary"}]}"#
        let events = """
        {"items":[
          {"id":"e1","status":"confirmed","summary":"Standup",
           "start":{"dateTime":"2026-05-25T10:00:00Z"},"end":{"dateTime":"2026-05-25T10:30:00Z"},
           "hangoutLink":"https://meet.google.com/abc"},
          {"id":"a1","status":"confirmed","summary":"Holiday","start":{"date":"2026-05-25"},"end":{"date":"2026-05-26"}}
        ]}
        """
        let http = StubHTTP(routes: [
            (match: { $0.path.hasSuffix("/calendarList") }, body: calList),
            (match: { $0.path.contains("/events") }, body: events),
        ])
        let provider = GoogleCalendarProvider(auth: FakeAuth(signedIn: true), http: http)
        provider.setEnabled(true)
        #expect(provider.isEnabled == true)
        let out = await provider.fetchEvents(start: Date(), end: Date().addingTimeInterval(3600))
        #expect(out.map(\.id) == ["e1"]) // all-day filtered out
        #expect(out.first?.source == .google)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter GoogleCalendarProvider`
Expected: FAIL — `GoogleCalendarProvider` undefined.

- [ ] **Step 3: Implement**

```swift
import Foundation

final class GoogleCalendarProvider: EventProvider {
    let kind: EventSourceKind = .google
    var onChange: (() -> Void)?

    /// Enabled only when the user toggled it on AND a session exists.
    private(set) var enabledFlag = false
    var isEnabled: Bool { enabledFlag && auth.isSignedIn }

    private let auth: GoogleAuthProviding
    private let api: GoogleCalendarAPI
    /// Per-calendar incremental sync tokens (Phase 7 uses these).
    private var syncTokens: [String: String] = [:]
    /// Last-known events per calendar, so incremental syncs can merge deltas.
    private var lastEvents: [String: [String: UpcomingEvent]] = [:]

    /// Called when auth transitions to needs-reauth.
    var onNeedsReauth: (() -> Void)?

    init(auth: GoogleAuthProviding, http: HTTPFetching = URLSession.shared) {
        self.auth = auth
        self.api = GoogleCalendarAPI(auth: auth, http: http)
    }

    func setEnabled(_ on: Bool) {
        enabledFlag = on
        if !on { syncTokens.removeAll(); lastEvents.removeAll() }
    }

    func start() { /* no observers; rides coordinator cadence */ }

    func fetchEvents(start: Date, end: Date) async -> [UpcomingEvent] {
        guard isEnabled else { return [] }
        do {
            let calendars = try await api.calendarIDs()
            var result: [UpcomingEvent] = []
            for cal in calendars {
                result.append(contentsOf: try await fetchCalendar(cal, start: start, end: end))
            }
            return result
        } catch GoogleCalendarAPIError.unauthorized, GoogleAuthError.needsReauth {
            onNeedsReauth?()
            return []
        } catch {
            // Transient: caller keeps last-known events.
            print("Tardy: Google fetch error: \(error)")
            return []
        }
    }

    private func fetchCalendar(_ cal: String, start: Date, end: Date) async throws -> [UpcomingEvent] {
        do {
            let resp = try await api.events(calendarID: cal, start: start, end: end, syncToken: syncTokens[cal])
            var byID = lastEvents[cal] ?? [:]
            for raw in resp.items {
                if raw.status == "cancelled" { byID[raw.id] = nil; continue }
                if let mapped = GoogleEventMapper.map(raw) { byID[raw.id] = mapped }
                else { byID[raw.id] = nil } // became all-day/declined → drop
            }
            // Prune events that fell outside the window.
            byID = byID.filter { $0.value.endDate > start && $0.value.startDate < end }
            lastEvents[cal] = byID
            if let token = resp.nextSyncToken { syncTokens[cal] = token }
            return Array(byID.values)
        } catch GoogleCalendarAPIError.syncTokenExpired {
            syncTokens[cal] = nil
            lastEvents[cal] = nil
            return try await fetchCalendar(cal, start: start, end: end) // full resync
        }
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter GoogleCalendarProvider`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Tardy/Calendar/Google/GoogleCalendarProvider.swift Tests/TardyTests/GoogleCalendarProviderTests.swift
git commit -m "feat: implement GoogleCalendarProvider with syncToken-aware fetch"
```

### Task 14: Wire the Google provider into the app

**Files:**
- Modify: `Sources/Tardy/App.swift`

- [ ] **Step 1: Add stored properties and construct the provider**

In `AppDelegate`, add properties near the top:
```swift
    private let googleAuth = GoogleSignInAuthService.shared
    private var googleProvider: GoogleCalendarProvider!
```

Replace the coordinator construction (added in Task 4) with:
```swift
        googleProvider = GoogleCalendarProvider(auth: googleAuth)
        googleProvider.setEnabled(settings.googleCalendarEnabled)   // SettingsManager flag, Task 15
        googleProvider.onNeedsReauth = { [weak self] in
            DispatchQueue.main.async { self?.menuBarController.setGoogleNeedsReauth(true) }
        }
        eventCoordinator = EventCoordinator(providers: [EventKitProvider(), googleProvider])
        eventCoordinator.delegate = self
        Task { await googleAuth.restorePreviousSignIn(); self.eventCoordinator.start() }
```

(Pass `googleAuth`, `googleProvider`, and `eventCoordinator` into `MenuBarController` in Task 16.)

- [ ] **Step 2: Build**

Run: `swift build`
Expected: FAIL until Tasks 15–16 add `settings.googleCalendarEnabled` and `menuBarController.setGoogleNeedsReauth`. Proceed; build green at end of Task 16.

- [ ] **Step 3: Commit**

```bash
git add Sources/Tardy/App.swift
git commit -m "feat: construct GoogleCalendarProvider and restore session at launch"
```

---

## Phase 6 — Settings UI & menu

### Task 15: Add `googleCalendarEnabled` to `SettingsManager` (TDD)

**Files:**
- Modify: `Sources/Tardy/Settings/SettingsManager.swift`
- Test: `Tests/TardyTests/SettingsManagerTests.swift`

- [ ] **Step 1: Write failing test** — append:

```swift
@Test("googleCalendarEnabled defaults to false and round-trips")
func googleCalendarEnabledFlag() {
    let s = SettingsManager(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
    #expect(s.googleCalendarEnabled == false)
    s.googleCalendarEnabled = true
    #expect(s.googleCalendarEnabled == true)
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter SettingsManager`
Expected: FAIL — property missing.

- [ ] **Step 3: Implement** — add the key constant and property to `SettingsManager`:

```swift
    private static let googleEnabledKey = "googleCalendarEnabled"

    var googleCalendarEnabled: Bool {
        get { defaults.bool(forKey: Self.googleEnabledKey) } // defaults to false
        set { defaults.set(newValue, forKey: Self.googleEnabledKey) }
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter SettingsManager`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Tardy/Settings/SettingsManager.swift Tests/TardyTests/SettingsManagerTests.swift
git commit -m "feat: persist googleCalendarEnabled setting"
```

### Task 16: Google section in Settings + menu re-auth indicator + poll-on-open

**Files:**
- Modify: `Sources/Tardy/Settings/SettingsView.swift`
- Modify: `Sources/Tardy/MenuBar/MenuBarController.swift`
- Modify: `Sources/Tardy/App.swift`

- [ ] **Step 1: Add an observable connection model + Google section to `SettingsView`**

Add at top of `SettingsView.swift` (after `import SwiftUI`):
```swift
import AppKit

@MainActor
final class GoogleConnectionModel: ObservableObject {
    @Published var email: String?
    @Published var isConnecting = false
    @Published var needsReauth = false
    var isConnected: Bool { email != nil }

    let connect: (@escaping () -> Void) -> Void   // calls back when done (refresh email)
    let disconnect: () -> Void

    init(email: String?, connect: @escaping (@escaping () -> Void) -> Void, disconnect: @escaping () -> Void) {
        self.email = email
        self.connect = connect
        self.disconnect = disconnect
    }
}
```

Add a stored model to `SettingsView` and a section. Change the struct's properties/init:
```swift
    let settings: SettingsManager
    let soundPlayer: SoundPlayer
    @ObservedObject var google: GoogleConnectionModel
```
and in `init` add `google: GoogleConnectionModel` param: `self.google = google`.

Insert before the `GENERAL` section (after the sound section's `settingsDivider`):
```swift
            settingsSection("GOOGLE CALENDAR") {
                VStack(alignment: .leading, spacing: 8) {
                    if let email = google.email {
                        HStack {
                            Text(email)
                                .font(.custom("Instrument Sans", size: 13))
                                .fontWeight(.semibold)
                                .foregroundColor(.white.opacity(0.7))
                            Spacer()
                            Button("Disconnect") { google.disconnect() }
                                .buttonStyle(.plain)
                                .font(.custom("Instrument Sans", size: 12))
                                .foregroundColor(Color(red: 248/255, green: 113/255, blue: 113/255).opacity(0.9))
                        }
                        if google.needsReauth {
                            Text("Session expired — reconnect to keep Google events.")
                                .font(.custom("Instrument Sans", size: 11))
                                .foregroundColor(Color(red: 251/255, green: 191/255, blue: 36/255).opacity(0.9))
                        }
                    } else {
                        Button(action: { google.isConnecting = true; google.connect { google.isConnecting = false } }) {
                            Text(google.isConnecting ? "Connecting…" : "Connect Google Account")
                                .font(.custom("Instrument Sans", size: 13))
                                .fontWeight(.semibold)
                                .foregroundColor(Color(red: 147/255, green: 197/255, blue: 253/255).opacity(0.95))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color(red: 59/255, green: 130/255, blue: 246/255).opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(google.isConnecting)
                    }
                }
            }
            settingsDivider
```

- [ ] **Step 2: Update `MenuBarController` to hold dependencies, build the model, add re-auth menu item, and poll-on-open**

Change `MenuBarController.init` to accept the auth, provider, settings flag toggling, and a refresh closure:
```swift
    private let googleAuth: GoogleAuthProviding
    private let onConnectGoogle: (@escaping () -> Void) -> Void   // performs sign-in using a presenting window
    private let onDisconnectGoogle: () -> Void
    private let onPollNow: () -> Void
    private var googleNeedsReauth = false

    init(settings: SettingsManager, soundPlayer: SoundPlayer,
         googleAuth: GoogleAuthProviding,
         onConnectGoogle: @escaping (@escaping () -> Void) -> Void,
         onDisconnectGoogle: @escaping () -> Void,
         onPollNow: @escaping () -> Void) {
        self.settings = settings
        self.soundPlayer = soundPlayer
        self.googleAuth = googleAuth
        self.onConnectGoogle = onConnectGoogle
        self.onDisconnectGoogle = onDisconnectGoogle
        self.onPollNow = onPollNow
    }

    func setGoogleNeedsReauth(_ on: Bool) {
        googleNeedsReauth = on
        rebuildMenu()
    }
```

In `rebuildMenu()`, before the `Settings...` item, add:
```swift
        if googleNeedsReauth {
            let reauth = NSMenuItem(title: "Reconnect Google…", action: #selector(openSettings), keyEquivalent: "")
            reauth.target = self
            menu.addItem(reauth)
        }
```

Add poll-on-open by setting the status item menu's delegate or triggering on open. Simplest: in `setup()` after creating `item`, store it; then have `rebuildMenu` attach a menu whose `menuWillOpen` calls `onPollNow`. Implement `NSMenuDelegate`:
```swift
    func menuWillOpen(_ menu: NSMenu) { onPollNow() }
```
and set `menu.delegate = self` in `rebuildMenu()` (declare `MenuBarController: NSObject, NSWindowDelegate, NSMenuDelegate`).

In `openSettings()`, build the connection model from the current window and pass it to `SettingsView`:
```swift
        let win = NSWindow(/* unchanged */)
        // ... after win is created and before contentView is set:
        let model = GoogleConnectionModel(
            email: googleAuth.isSignedIn ? googleAuth.accountEmail : nil,
            connect: { [weak self, weak win] done in
                guard let self, let win else { return }
                self.onConnectGoogle { /* completion on main */ done() }
                // refresh email after connect completes:
            },
            disconnect: { [weak self] in self?.onDisconnectGoogle() }
        )
        model.needsReauth = googleNeedsReauth
        let view = SettingsView(settings: settings, soundPlayer: soundPlayer, google: model)
        let hostingView = NSHostingView(rootView: view)
        win.contentView = hostingView
```
After a successful connect, set `model.email = googleAuth.accountEmail`, `model.needsReauth = false`, and call `setGoogleNeedsReauth(false)`. (Have the `onConnectGoogle` completion update the model on the main actor.)

- [ ] **Step 3: Wire closures in `App.swift`**

Replace `menuBarController = MenuBarController(settings: settings, soundPlayer: soundPlayer)` (`App.swift:17`) with:
```swift
        menuBarController = MenuBarController(
            settings: settings,
            soundPlayer: soundPlayer,
            googleAuth: googleAuth,
            onConnectGoogle: { [weak self] done in
                guard let self else { return }
                let anchor = NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow()
                Task { @MainActor in
                    do {
                        try await self.googleAuth.signIn(presenting: anchor)
                        self.settings.googleCalendarEnabled = true
                        self.googleProvider.setEnabled(true)
                        self.menuBarController.setGoogleNeedsReauth(false)
                        self.eventCoordinator.refresh(forceReschedule: true)
                    } catch { /* cancelled or failed: leave disconnected */ }
                    done()
                }
            },
            onDisconnectGoogle: { [weak self] in
                guard let self else { return }
                self.googleAuth.signOut()
                self.settings.googleCalendarEnabled = false
                self.googleProvider.setEnabled(false)
                self.eventCoordinator.refresh(forceReschedule: true)
            },
            onPollNow: { [weak self] in self?.eventCoordinator.refresh() }
        )
```

- [ ] **Step 4: Build and run the full suite**

Run: `swift build && swift test`
Expected: PASS, clean build.

- [ ] **Step 5: Manual smoke test**

```bash
./scripts/build-app.sh 0.2.0-dev && open .build/app/Tardy.app
```
- Open Settings → "Connect Google Account" → complete consent (test user) → email appears.
- Confirm a Google-only event shows in the menu's "Next:" line.
- Disconnect → Google events disappear, EventKit remains.

- [ ] **Step 6: Commit**

```bash
git add Sources/Tardy/Settings/SettingsView.swift Sources/Tardy/MenuBar/MenuBarController.swift Sources/Tardy/App.swift
git commit -m "feat: Google connect/disconnect settings UI, re-auth menu item, poll-on-open"
```

---

## Phase 7 — Adaptive near-term polling

`syncToken` (Task 12/13) is already in place. This phase adds tighter polling as an event approaches, so last-minute changes are caught before the alert fires.

### Task 17: Adaptive near-term poll in `EventCoordinator` (TDD)

**Files:**
- Modify: `Sources/Tardy/Calendar/EventCoordinator.swift`
- Test: `Tests/TardyTests/EventCoordinatorTests.swift`

- [ ] **Step 1: Write a failing test for the poll-interval policy**

Extract the decision into a pure function so it's testable without timers:

```swift
import Testing
import Foundation
@testable import Tardy

@Suite("EventCoordinator near-term polling")
struct EventCoordinatorTests {
    @Test("polls every 30s when an event is within 5 minutes")
    func tightWhenImminent() {
        let next = Date().addingTimeInterval(120)
        #expect(EventCoordinator.nearTermPollInterval(nextStart: next, now: Date()) == 30)
    }
    @Test("no near-term poll when next event is far away")
    func looseWhenFar() {
        let next = Date().addingTimeInterval(3600)
        #expect(EventCoordinator.nearTermPollInterval(nextStart: next, now: Date()) == nil)
    }
    @Test("no near-term poll when there is no upcoming event")
    func noneWhenEmpty() {
        #expect(EventCoordinator.nearTermPollInterval(nextStart: nil, now: Date()) == nil)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter "EventCoordinator near-term polling"`
Expected: FAIL — `nearTermPollInterval` undefined.

- [ ] **Step 3: Implement the policy + schedule a near-term timer after each refresh**

Add the pure policy to `EventCoordinator`:
```swift
    /// Returns the polling interval (seconds) to use when the next event is
    /// imminent, or nil when no tight polling is needed.
    static func nearTermPollInterval(nextStart: Date?, now: Date) -> TimeInterval? {
        guard let nextStart else { return nil }
        let delta = nextStart.timeIntervalSince(now)
        guard delta > 0, delta <= 5 * 60 else { return nil }
        return 30
    }
```

Add a near-term timer and (re)arm it whenever we merge. In `refresh()`, after computing `merged` and before notifying the delegate, capture the next start and arm the timer on the main actor:
```swift
            let nextStart = merged.first(where: { $0.startDate > Date() })?.startDate
            await MainActor.run {
                self.armNearTermTimer(nextStart: nextStart)
                self.delegate?.eventCoordinator(self, didUpdateEvents: merged, forceReschedule: forceReschedule)
            }
```
Add the timer storage + arming:
```swift
    private var nearTermTimer: Timer?

    private func armNearTermTimer(nextStart: Date?) {
        nearTermTimer?.invalidate(); nearTermTimer = nil
        guard let interval = Self.nearTermPollInterval(nextStart: nextStart, now: Date()) else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        nearTermTimer = timer
    }
```
Also invalidate it in `stop()`: add `nearTermTimer?.invalidate(); nearTermTimer = nil`.

- [ ] **Step 4: Run to verify pass + full suite**

Run: `swift test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Tardy/Calendar/EventCoordinator.swift Tests/TardyTests/EventCoordinatorTests.swift
git commit -m "feat: adaptive near-term polling for imminent events"
```

---

## Phase 8 — Beta & public verification (process, no app code)

### Task 18: Beta in Testing mode

- [ ] **Step 1: Verify end-to-end with a test user**

Build, launch, connect, and confirm Google events merge with EventKit without duplicates over a real day (including an event that has a Meet link and one phone-only event).

- [ ] **Step 2: Document the 7-day re-auth behavior**

Confirm that after a test-mode refresh token expires, the menu shows "Reconnect Google…" and reconnecting restores events. Note this in the README's Google section.

- [ ] **Step 3: Commit README note**

```bash
git add README.md
git commit -m "docs: document Google Calendar connection + test-mode re-auth"
```

### Task 19: Prepare public OAuth verification

- [ ] **Step 1: Publish static homepage + privacy policy**

Host a homepage and a privacy policy (e.g., GitHub Pages on a custom domain). Privacy policy states: "Tardy reads upcoming calendar events to show reminders; data never leaves your device." Verify domain ownership in Search Console.

- [ ] **Step 2: Submit for verification in the Console**

OAuth consent screen → add app logo, homepage URL, privacy-policy URL, authorized domain; record a demo video showing the consent flow + scope usage; submit the `calendar.readonly` scope justification. (No CASA assessment — `calendar.readonly` is sensitive, not restricted.)

- [ ] **Step 3: After approval, publish to Production**

Switch publishing status to "In production." No code change — the same client ID now serves all users without the warning or 100-user cap.

---

## Self-Review Notes (verified against spec)

- **Multi-source + merge/dedupe:** Tasks 2–5, 13–14. ✅
- **GoogleSignIn for auth only:** Tasks 8–9. ✅
- **No-secret Apple client + PKCE + Info.plist scheme:** Tasks 6–7. ✅
- **`calendar.readonly` scope:** Tasks 6, 9 (`GoogleOAuthConfig.scopes`). ✅
- **Conference extraction (video→hangoutLink→scrape; phone):** Task 11. ✅
- **Filtering (all-day/cancelled/declined):** Task 11 (Google), preserved for EventKit in Task 3. ✅
- **iCalUID dedupe + (start,title) fallback + prefer Google:** Task 5. ✅
- **Freshness: existing cadence (Task 4), syncToken (12/13), adaptive near-term (17), poll-on-open (16).** ✅
- **Settings connect/disconnect + re-auth state:** Tasks 15–16. ✅
- **Error handling (401→reauth, 410→resync, transient keeps last-known, degrade to EventKit):** Tasks 12–14. ✅
- **Verification/website track:** Tasks 18–19. ✅
- **Naming consistency check:** `EventSourceKind`, `EventProvider`, `EventCoordinator`/`EventCoordinatorDelegate`, `EventDeduplicator.merge`, `GoogleAuthProviding`/`GoogleSignInAuthService`/`GoogleAuthError`, `GoogleCalendarAPI`/`GoogleCalendarAPIError`, `HTTPFetching`, `GoogleEventMapper.map`, `GoogleCalendarProvider.setEnabled/onNeedsReauth`, `SettingsManager.googleCalendarEnabled`, `UpcomingEvent.source/iCalUID` — used consistently across tasks. ✅
