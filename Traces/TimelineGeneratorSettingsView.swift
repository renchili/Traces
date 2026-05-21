import SwiftUI

// MARK: - Timeline import settings popover
// This file owns only the settings UI shown from the toolbar. Values are passed
// in as bindings from TracesViewModel; this view does not import files or call
// Google APIs directly.

/// Settings panel for Timeline JSON generation.
///
/// Controlled UI:
/// - Google API key input
/// - location cache count and clear button
/// - import date range
/// - minimum stay threshold
/// - long home-like stay filtering threshold
struct TimelineGeneratorSettingsView: View {
    @Binding var googleAPIKey: String
    @Binding var lastDays: Int
    @Binding var minStayMinutes: Double
    @Binding var removeHomeOverMinutes: Double

    let cacheCount: Int
    let onClearCache: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Timeline Generation")
                    .font(.headline)

                Text("Resolve unique placeIDs first, cache successful results locally, then generate calendar events.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // API key is stored by the view model. This is acceptable for local
            // development; production distribution should move it to Keychain or
            // a backend resolver.
            VStack(alignment: .leading, spacing: 6) {
                Text("Google API Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SecureField("Places API / Geocoding API key", text: $googleAPIKey)
                    .textFieldStyle(.roundedBorder)

                Text("Only uncached placeIDs call Google APIs. Cached historical locations are reused without refresh.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // Cache actions only affect future location resolution. Existing
            // imported events remain unchanged until re-imported.
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Location Cache")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(cacheCount) cached places")
                        .font(.system(size: 13))
                }

                Spacer()

                Button("Clear Cache") {
                    onClearCache()
                }
            }

            Divider()

            // These settings are applied the next time a Timeline JSON file is opened.
            VStack(alignment: .leading, spacing: 10) {
                SettingStepperRow(
                    title: "Date range",
                    valueText: "\(lastDays) days",
                    systemImage: "calendar",
                    onMinus: { lastDays = max(1, lastDays - 1) },
                    onPlus: { lastDays = min(365, lastDays + 1) }
                )

                SettingStepperRow(
                    title: "Minimum stay",
                    valueText: "\(Int(minStayMinutes)) min",
                    systemImage: "clock",
                    onMinus: { minStayMinutes = max(1, minStayMinutes - 5) },
                    onPlus: { minStayMinutes = min(180, minStayMinutes + 5) }
                )

                SettingStepperRow(
                    title: "Remove Home over",
                    valueText: "\(Int(removeHomeOverMinutes)) min",
                    systemImage: "house",
                    onMinus: {
                        removeHomeOverMinutes = max(15, removeHomeOverMinutes - 15)
                    },
                    onPlus: {
                        removeHomeOverMinutes = min(720, removeHomeOverMinutes + 15)
                    }
                )
            }

            Text("Reopen the Timeline JSON after changing generation settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 440)
    }
}

/// Reusable stepper row used by the settings panel.
struct SettingStepperRow: View {
    let title: String
    let valueText: String
    let systemImage: String
    let onMinus: () -> Void
    let onPlus: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(valueText)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 72, alignment: .trailing)

            HStack(spacing: 0) {
                Button(action: onMinus) {
                    Image(systemName: "minus")
                        .frame(width: 24, height: 22)
                }

                Divider()
                    .frame(height: 18)

                Button(action: onPlus) {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 22)
                }
            }
            .buttonStyle(.borderless)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
        }
        .font(.system(size: 13))
    }
}
