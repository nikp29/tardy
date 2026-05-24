import Foundation

enum GoogleCalendarModels {
    /// RFC3339 decoder. Google returns `dateTime` like 2026-05-25T10:00:00-04:00
    /// (sometimes with fractional seconds).
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
