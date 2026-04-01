import Foundation

struct UpcomingEvent: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let location: String?
    let conferenceURL: URL?
    let phoneNumber: String?
    let notes: String?

    /// Equality is based on id only (for Set/Dictionary lookups).
    static func == (lhs: UpcomingEvent, rhs: UpcomingEvent) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// Returns true if any display-relevant field differs.
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
