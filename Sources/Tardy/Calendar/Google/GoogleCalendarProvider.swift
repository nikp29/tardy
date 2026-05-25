import Foundation

final class GoogleCalendarProvider: EventProvider {
    let kind: EventSourceKind = .google
    var onChange: (() -> Void)?

    /// Enabled only when the user toggled it on AND a session exists.
    private(set) var enabledFlag = false
    var isEnabled: Bool { enabledFlag && auth.isSignedIn }

    private let auth: GoogleAuthProviding
    private let api: GoogleCalendarAPI
    /// Per-calendar incremental sync tokens (dormant while windowed queries set
    /// orderBy/timeMin/timeMax, which the API won't return a syncToken for).
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

        let calendars: [String]
        do {
            calendars = try await api.calendarIDs()
        } catch GoogleCalendarAPIError.unauthorized, GoogleAuthError.needsReauth {
            onNeedsReauth?()
            return []
        } catch {
            NSLog("Tardy: Google calendarList error: \(error)")
            return []
        }

        // Fetch each calendar independently. A single failing calendar (e.g. a
        // shared/holiday calendar that errors) must NOT wipe out the others.
        var result: [UpcomingEvent] = []
        for cal in calendars {
            do {
                result.append(contentsOf: try await fetchCalendar(cal, start: start, end: end))
            } catch GoogleCalendarAPIError.unauthorized, GoogleAuthError.needsReauth {
                onNeedsReauth?()
                return result
            } catch {
                NSLog("Tardy: Google events error for calendar \(cal): \(error)")
                continue
            }
        }
        return result
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
