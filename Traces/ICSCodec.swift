import Foundation

// MARK: - ICS writer
// Converts the current final ICSEvent list into an .ics calendar file.
// Conflict candidates are kept in app/session data for review, but only the
// current final event itself is exported as a VEVENT.

final class ICSWriter {
    /// Creates a complete VCALENDAR document for the supplied final events.
    static func makeICS(events: [ICSEvent]) -> String {
        let now = utcICSDate(Date())

        var lines: [String] = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Traces//Google Timeline Preview//EN",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH"
        ]

        for event in events {
            lines.append("BEGIN:VEVENT")
            lines.append("UID:\(event.id)")
            lines.append("DTSTAMP:\(now)")

            if let start = event.start {
                lines.append("DTSTART:\(utcICSDate(start))")
            }

            if let end = event.end {
                lines.append("DTEND:\(utcICSDate(end))")
            }

            lines.append("SUMMARY:\(escape(event.summary))")

            if !event.location.isEmpty {
                lines.append("LOCATION:\(escape(event.location))")
            }

            if !event.description.isEmpty {
                lines.append("DESCRIPTION:\(escape(event.description))")
            }

            if !event.url.isEmpty {
                lines.append("URL:\(event.url)")
            }

            // GEO is supported by many calendar clients and keeps the coordinate
            // available even when location text is only an address/place name.
            if let lat = event.lat, let lon = event.lon {
                lines.append("GEO:\(String(format: "%.6f", lat));\(String(format: "%.6f", lon))")
            }

            lines.append("END:VEVENT")
        }

        lines.append("END:VCALENDAR")

        var output = ""
        for line in lines {
            output += foldLine(line)
        }

        return output
    }

    /// ICS UTC timestamp formatter, e.g. 20260521T120000Z.
    private static func utcICSDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.string(from: date)
    }

    /// Escapes text according to basic iCalendar text rules.
    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ";", with: "\\;")
    }

    /// Folds long ICS lines with CRLF + space continuation.
    private static func foldLine(_ line: String) -> String {
        guard line.count > 73 else {
            return line + "\r\n"
        }

        var rest = line
        var out = ""

        while rest.count > 73 {
            let index = rest.index(rest.startIndex, offsetBy: 73)
            out += String(rest[..<index]) + "\r\n "
            rest = String(rest[index...])
        }

        return out + rest + "\r\n"
    }
}

// MARK: - ICS parser
// Lightweight parser used for previewing existing .ics files. It is intentionally
// conservative and extracts only the fields Traces can display/export again.

final class ICSParser {
    /// Parses VEVENT blocks into ICSEvent values for preview.
    static func parse(_ text: String) -> [ICSEvent] {
        let unfolded = unfoldICS(text)
        let lines = unfolded.components(separatedBy: .newlines)

        var events: [ICSEvent] = []
        var current: [String: String]?
        var uid = UUID().uuidString

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .newlines)

            if line == "BEGIN:VEVENT" {
                current = [:]
                uid = UUID().uuidString
                continue
            }

            if line == "END:VEVENT" {
                if let current {
                    let geo = parseGEO(current["GEO"])

                    events.append(
                        ICSEvent(
                            id: current["UID"] ?? uid,
                            summary: unescape(current["SUMMARY"] ?? "(No title)"),
                            location: unescape(current["LOCATION"] ?? ""),
                            description: unescape(current["DESCRIPTION"] ?? ""),
                            url: current["URL"] ?? "",
                            start: parseICSDate(current["DTSTART"]),
                            end: parseICSDate(current["DTEND"]),
                            lat: geo?.lat,
                            lon: geo?.lon,
                            suppressedCandidates: []
                        )
                    )
                }

                current = nil
                continue
            }

            guard current != nil else { continue }

            if let idx = line.firstIndex(of: ":") {
                var key = String(line[..<idx])
                let value = String(line[line.index(after: idx)...])

                // Drop parameters such as DTSTART;TZID=... so the storage key is
                // just DTSTART. This parser does not currently preserve TZID.
                if let semi = key.firstIndex(of: ";") {
                    key = String(key[..<semi])
                }

                current?[key] = value
            }
        }

        return events.sorted {
            ($0.start ?? .distantPast) < ($1.start ?? .distantPast)
        }
    }

    /// Joins folded ICS continuation lines before parsing key/value pairs.
    private static func unfoldICS(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var result: [String] = []

        for line in normalized.components(separatedBy: "\n") {
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                if !result.isEmpty {
                    result[result.count - 1] += String(line.dropFirst())
                }
            } else {
                result.append(line)
            }
        }

        return result.joined(separator: "\n")
    }

    /// Reverses the basic escaping done by ICSWriter.
    private static func unescape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    /// Supports UTC datetime, floating datetime, and date-only values.
    private static func parseICSDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }

        let formats = [
            "yyyyMMdd'T'HHmmss'Z'",
            "yyyyMMdd'T'HHmmss",
            "yyyyMMdd"
        ]

        for format in formats {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = value.hasSuffix("Z") ? TimeZone(secondsFromGMT: 0) : .current

            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }

    /// Parses GEO:lat;lon into coordinate fields on ICSEvent.
    private static func parseGEO(_ value: String?) -> (lat: Double, lon: Double)? {
        guard let value else { return nil }

        let parts = value.split(separator: ";")
        guard
            parts.count == 2,
            let lat = Double(parts[0]),
            let lon = Double(parts[1])
        else {
            return nil
        }

        return (lat, lon)
    }
}
