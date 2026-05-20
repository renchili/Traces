//
//  ICSCodec.swift
//  Traces
//
//  Created by Renchi Li on 20/5/26.
//

import Foundation

final class ICSWriter {
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

            lines.append("END:VEVENT")
        }

        lines.append("END:VCALENDAR")

        var output = ""
        for line in lines {
            output += foldLine(line)
        }

        return output
    }

    private static func utcICSDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.string(from: date)
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ";", with: "\\;")
    }

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

final class ICSParser {
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
                    events.append(
                        ICSEvent(
                            id: current["UID"] ?? uid,
                            summary: unescape(current["SUMMARY"] ?? "(No title)"),
                            location: unescape(current["LOCATION"] ?? ""),
                            description: unescape(current["DESCRIPTION"] ?? ""),
                            url: current["URL"] ?? "",
                            start: parseICSDate(current["DTSTART"]),
                            end: parseICSDate(current["DTEND"])
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

    private static func unescape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

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
}
