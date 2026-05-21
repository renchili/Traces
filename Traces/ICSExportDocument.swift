import SwiftUI
import UniformTypeIdentifiers

// MARK: - SwiftUI ICS export document
// Used by ContentView.fileExporter instead of manually creating NSSavePanel.
// This keeps export in SwiftUI and avoids AppKit save-panel crashes.

struct ICSExportDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [UTType(filenameExtension: "ics") ?? .data]
    }

    static var writableContentTypes: [UTType] {
        [UTType(filenameExtension: "ics") ?? .data]
    }

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let text = String(data: data, encoding: .utf8) {
            self.text = text
        } else {
            self.text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
