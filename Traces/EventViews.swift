//
//  EventViews.swift
//  Traces
//
//  Created by Renchi Li on 20/5/26.
//

import SwiftUI
import Foundation

struct EventRow: View {
    let event: ICSEvent
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.summary)
                .font(.headline)
                .lineLimit(compact ? 2 : 1)
                .truncationMode(.tail)

            if !compact {
                Text(dateRange(event))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !event.location.isEmpty {
                    Text(event.location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct EventDetailView: View {
    let event: ICSEvent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(event.summary)
                    .font(.largeTitle.bold())
                    .textSelection(.enabled)

                VStack(alignment: .leading, spacing: 8) {
                    Label(dateRange(event), systemImage: "calendar")

                    if !event.location.isEmpty {
                        Label(event.location, systemImage: "mappin.and.ellipse")
                            .textSelection(.enabled)
                    }

                    if !event.url.isEmpty, let url = URL(string: event.url) {
                        Link(event.url, destination: url)
                    }
                }

                if !event.description.isEmpty {
                    Divider()

                    Text(event.description)
                        .textSelection(.enabled)
                        .font(.body)
                }

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

func dateRange(_ event: ICSEvent) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short

    switch (event.start, event.end) {
    case let (start?, end?):
        return "\(formatter.string(from: start)) → \(formatter.string(from: end))"
    case let (start?, nil):
        return formatter.string(from: start)
    default:
        return "No time"
    }
}
