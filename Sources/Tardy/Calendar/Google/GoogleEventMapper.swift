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
