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
    /// performs an incremental sync instead (timeMin/timeMax/orderBy omitted, per
    /// API rules — those params are incompatible with syncToken).
    func events(calendarID: String, start: Date, end: Date, syncToken: String?) async throws -> GoogleEventsResponse {
        // Encode the calendar ID as a single path segment. Calendar IDs contain
        // '@' and sometimes '#' (e.g. en.usa#holiday@...), which must be escaped.
        // Build the URL string directly (appendingPathComponent would re-encode
        // the '%' and double-escape).
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encodedID = calendarID.addingPercentEncoding(withAllowedCharacters: allowed) ?? calendarID
        var comps = URLComponents(string: base.absoluteString + "calendars/\(encodedID)/events")!
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
