import SwiftUI
import Foundation

// MARK: - Timeline waterfall
// Owns the right-side time overview. This file renders timed events as vertical
// blocks, handles overlap columns, date separators, and highlights the selected event.

/// Right-side timeline panel shown in the main three-pane layout.
struct TimelineWaterfallView: View {
    let events: [ICSEvent]
    @Binding var selectedEventID: String?

    private var datedEvents: [ICSEvent] {
        events
            .filter { $0.start != nil && $0.end != nil }
            .sorted { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }
    }

    private var dayStart: Date? {
        guard let first = datedEvents.first?.start else { return nil }
        return Calendar.current.startOfDay(for: first)
    }

    private var dayEnd: Date? {
        guard let last = datedEvents.compactMap(\.end).max() else { return nil }
        return Calendar.current.date(
            byAdding: .day,
            value: 1,
            to: Calendar.current.startOfDay(for: last)
        )
    }

    private var dateRangeText: String {
        guard let first = datedEvents.first?.start,
              let last = datedEvents.compactMap(\.end).max()
        else {
            return "No dates"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        if Calendar.current.isDate(first, inSameDayAs: last) {
            return formatter.string(from: first)
        }

        return "\(formatter.string(from: first)) → \(formatter.string(from: last))"
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(220, proxy.size.width)
            let widthBucket = Int(width.rounded())

            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Timeline")
                            .font(.headline)

                        Text(dateRangeText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    Text("\(datedEvents.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Divider()

                if datedEvents.isEmpty {
                    ContentUnavailableView(
                        "No timed events",
                        systemImage: "timeline.selection",
                        description: Text("Open Timeline JSON or ICS with event times.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { reader in
                        ScrollView {
                            TimelineCanvas(
                                events: datedEvents,
                                selectedEventID: $selectedEventID,
                                dayStart: dayStart,
                                dayEnd: dayEnd,
                                availableWidth: width - 24
                            )
                            .padding(12)
                            .id(widthBucket)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear {
                            scrollToSelected(reader)
                        }
                        .onChange(of: selectedEventID) { _, _ in
                            scrollToSelected(reader)
                        }
                        .onChange(of: events.map(\.id)) { _, _ in
                            scrollToSelected(reader)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(.background)
        }
    }

    private func scrollToSelected(_ reader: ScrollViewProxy) {
        guard let selectedEventID else { return }

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.25)) {
                reader.scrollTo(selectedEventID, anchor: .center)
            }
        }
    }
}

/// Draws the hour grid and places event blocks into non-overlapping columns.
struct TimelineCanvas: View {
    let events: [ICSEvent]
    @Binding var selectedEventID: String?
    let dayStart: Date?
    let dayEnd: Date?
    let availableWidth: CGFloat

    private let hourHeight: CGFloat = 52
    private let labelWidth: CGFloat = 54
    private let columnGap: CGFloat = 6
    private let contentLeftPadding: CGFloat = 8
    private let contentRightPadding: CGFloat = 8

    private struct LayoutItem: Identifiable {
        let id: String
        let event: ICSEvent
        let column: Int
        let totalColumns: Int
    }

    private var totalHours: CGFloat {
        guard let dayStart, let dayEnd else { return 24 }
        return max(24, CGFloat(dayEnd.timeIntervalSince(dayStart) / 3600.0))
    }

    private var canvasHeight: CGFloat {
        totalHours * hourHeight
    }

    private var canvasWidth: CGFloat {
        max(220, availableWidth)
    }

    private var dayCount: Int {
        guard let dayStart, let dayEnd else { return 1 }
        return max(1, Calendar.current.dateComponents([.day], from: dayStart, to: dayEnd).day ?? 1)
    }

    var body: some View {
        let layoutItems = makeLayoutItems()

        ZStack(alignment: .topLeading) {
            hourGrid(totalWidth: canvasWidth)
            dateSeparators(totalWidth: canvasWidth)

            ForEach(layoutItems, id: \.id) { item in
                if let rect = rectForEvent(item, totalWidth: canvasWidth) {
                    TimelineEventBlock(
                        event: item.event,
                        isSelected: item.event.id == selectedEventID,
                        compact: rect.width < 110
                    )
                    .frame(width: rect.width, height: rect.height, alignment: .topLeading)
                    .position(x: rect.midX, y: rect.midY)
                    .id(item.event.id)
                    .onTapGesture {
                        if selectedEventID == item.event.id {
                            selectedEventID = nil
                        } else {
                            selectedEventID = item.event.id
                        }
                    }
                    .zIndex(item.event.id == selectedEventID ? 10 : 1)
                }
            }
        }
        .frame(width: canvasWidth, height: canvasHeight, alignment: .topLeading)
    }

    private func dateSeparators(totalWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<dayCount, id: \.self) { dayOffset in
                if let date = Calendar.current.date(byAdding: .day, value: dayOffset, to: dayStart ?? Date()) {
                    let y = CGFloat(dayOffset * 24) * hourHeight

                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color.accentColor.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(Color.accentColor.opacity(0.20), lineWidth: 1)
                        )
                        .frame(width: max(120, totalWidth - labelWidth), height: 24)
                        .position(x: labelWidth + (totalWidth - labelWidth) / 2, y: y + 12)

                    Text(dayLabel(date))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                        .position(x: labelWidth + 64, y: y + 12)
                }
            }
        }
    }

    private func hourGrid(totalWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0...Int(totalHours), id: \.self) { hour in
                let y = CGFloat(hour) * hourHeight
                let isDayStart = hour % 24 == 0

                Path { path in
                    path.move(to: CGPoint(x: labelWidth, y: y))
                    path.addLine(to: CGPoint(x: totalWidth, y: y))
                }
                .stroke(isDayStart ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.18), lineWidth: isDayStart ? 1.3 : 1)

                Text(hourLabel(hour))
                    .font(.caption2)
                    .foregroundStyle(isDayStart ? Color.accentColor : .secondary)
                    .frame(width: labelWidth - 8, alignment: .trailing)
                    .position(x: (labelWidth - 8) / 2, y: y + 7)
            }
        }
    }

    private func makeLayoutItems() -> [LayoutItem] {
        let sorted = events.sorted {
            let lhs = $0.start ?? .distantPast
            let rhs = $1.start ?? .distantPast

            if lhs == rhs {
                return ($0.end ?? .distantPast) < ($1.end ?? .distantPast)
            }

            return lhs < rhs
        }

        var groups: [[ICSEvent]] = []
        var currentGroup: [ICSEvent] = []
        var currentGroupMaxEnd: Date?

        for event in sorted {
            guard let start = event.start, let end = event.end else {
                continue
            }

            if let groupEnd = currentGroupMaxEnd, start < groupEnd {
                currentGroup.append(event)

                if end > groupEnd {
                    currentGroupMaxEnd = end
                }
            } else {
                if !currentGroup.isEmpty {
                    groups.append(currentGroup)
                }

                currentGroup = [event]
                currentGroupMaxEnd = end
            }
        }

        if !currentGroup.isEmpty {
            groups.append(currentGroup)
        }

        var result: [LayoutItem] = []

        for group in groups {
            result.append(contentsOf: layoutGroup(group))
        }

        return result
    }

    private func layoutGroup(_ group: [ICSEvent]) -> [LayoutItem] {
        let sorted = group.sorted {
            let lhs = $0.start ?? .distantPast
            let rhs = $1.start ?? .distantPast

            if lhs == rhs {
                return ($0.end ?? .distantPast) < ($1.end ?? .distantPast)
            }

            return lhs < rhs
        }

        var columnEndDates: [Date] = []
        var temporary: [(event: ICSEvent, column: Int)] = []

        for event in sorted {
            guard let start = event.start, let end = event.end else {
                continue
            }

            var assignedColumn: Int?

            for index in columnEndDates.indices {
                if start >= columnEndDates[index] {
                    assignedColumn = index
                    columnEndDates[index] = end
                    break
                }
            }

            if assignedColumn == nil {
                columnEndDates.append(end)
                assignedColumn = columnEndDates.count - 1
            }

            temporary.append((event: event, column: assignedColumn ?? 0))
        }

        let totalColumns = max(1, columnEndDates.count)

        return temporary.map {
            LayoutItem(
                id: $0.event.id,
                event: $0.event,
                column: $0.column,
                totalColumns: totalColumns
            )
        }
    }

    private func rectForEvent(_ item: LayoutItem, totalWidth: CGFloat) -> CGRect? {
        guard
            let dayStart,
            let start = item.event.start,
            let end = item.event.end
        else {
            return nil
        }

        let startHours = max(0, start.timeIntervalSince(dayStart) / 3600.0)
        let endHours = max(startHours + 0.15, end.timeIntervalSince(dayStart) / 3600.0)

        let y = CGFloat(startHours) * hourHeight
        let height = max(30, CGFloat(endHours - startHours) * hourHeight)

        let usableWidth = max(
            90,
            totalWidth - labelWidth - contentLeftPadding - contentRightPadding
        )

        let totalGap = CGFloat(max(0, item.totalColumns - 1)) * columnGap
        let columnWidth = max(
            56,
            (usableWidth - totalGap) / CGFloat(item.totalColumns)
        )

        let x =
            labelWidth
            + contentLeftPadding
            + CGFloat(item.column) * (columnWidth + columnGap)

        return CGRect(
            x: x,
            y: y,
            width: columnWidth,
            height: height
        )
    }

    private func hourLabel(_ hourOffset: Int) -> String {
        guard let dayStart else {
            return "\(hourOffset):00"
        }

        let date = Calendar.current.date(byAdding: .hour, value: hourOffset, to: dayStart) ?? dayStart
        let formatter = DateFormatter()
        formatter.dateFormat = hourOffset % 24 == 0 ? "MMM d" : "HH:mm"
        return formatter.string(from: date)
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, d MMM yyyy"
        return formatter.string(from: date)
    }
}

/// One visual event block in the waterfall.
struct TimelineEventBlock: View {
    let event: ICSEvent
    let isSelected: Bool
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(event.summary)
                    .font(.caption.bold())
                    .lineLimit(compact ? 1 : 2)
                    .truncationMode(.tail)

                if !event.suppressedCandidates.isEmpty {
                    Text("+\(event.suppressedCandidates.count)")
                        .font(.caption2.bold())
                        .foregroundStyle(.orange)
                }
            }

            Text(shortDateTimeRange(event))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)
        }
        .padding(compact ? 5 : 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.24) : Color.secondary.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.20),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .clipped()
    }

    private func shortDateTimeRange(_ event: ICSEvent) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"

        guard let start = event.start else {
            return "No time"
        }

        let datePrefix = dateFormatter.string(from: start)

        if let end = event.end {
            if Calendar.current.isDate(start, inSameDayAs: end) {
                return "\(datePrefix) · \(timeFormatter.string(from: start)) → \(timeFormatter.string(from: end))"
            }

            return "\(datePrefix) \(timeFormatter.string(from: start)) → \(dateFormatter.string(from: end)) \(timeFormatter.string(from: end))"
        }

        return "\(datePrefix) · \(timeFormatter.string(from: start))"
    }
}
