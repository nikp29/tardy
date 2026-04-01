import Foundation

enum ConferenceInfo: Equatable {
    case videoCall(URL, provider: String)
    case phone(String)
    case notes(String)
}

struct ConferenceLinkExtractor {

    private static let providers: [(pattern: String, name: String)] = [
        (#"https?://[\w.-]*zoom\.us/j/[^\s"<>]+"#, "Zoom"),
        (#"https?://meet\.google\.com/[^\s"<>]+"#, "Google Meet"),
        (#"https?://teams\.microsoft\.com/l/meetup-join/[^\s"<>]+"#, "Teams"),
        (#"https?://[\w.-]*\.webex\.com/[^\s"<>]+"#, "Webex"),
        (#"https?://meet\.around\.co/[^\s"<>]+"#, "Around"),
        (#"https?://whereby\.com/[^\s"<>]+"#, "Whereby"),
    ]

    private static let phonePattern = #"(\+?\d[\d\-.\s]{6,}\d|\(\d{3}\)\s*\d{3}[-.]\d{4})"#

    static func extract(url: URL?, notes: String?, location: String?) -> ConferenceInfo? {
        let urlString = url?.absoluteString
        let sources = [urlString, notes, location].compactMap { $0 }

        // 1. Look for a known video call URL across all sources
        for source in sources {
            if let match = findVideoURL(in: source) {
                return match
            }
        }

        // 2. Look for a phone number across all sources
        for source in sources {
            if let phone = findPhone(in: source) {
                return .phone(phone)
            }
        }

        // 3. Fall back to raw notes
        if let notes, !notes.isEmpty {
            return .notes(notes)
        }

        return nil
    }

    private static func findVideoURL(in text: String) -> ConferenceInfo? {
        for (pattern, name) in providers {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, options: [], range: range),
               let matchRange = Range(match.range, in: text),
               let url = URL(string: String(text[matchRange])) {
                return .videoCall(url, provider: name)
            }
        }
        return nil
    }

    private static func findPhone(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: phonePattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        if let match = regex.firstMatch(in: text, options: [], range: range),
           let matchRange = Range(match.range, in: text) {
            return String(text[matchRange])
        }
        return nil
    }
}
