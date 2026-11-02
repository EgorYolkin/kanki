import SwiftUI
import UniformTypeIdentifiers

struct CardExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let archive: CardExportArchive

    init(archive: CardExportArchive) {
        self.archive = archive
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        archive = try CardExportArchive.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try archive.encoded())
    }
}

struct CardExportScreen: View {
    let cards: [SessionCard]
    let onExport: (Set<UUID>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<UUID> = []

    var body: some View {
        NavigationStack {
            selectionList
            .safeAreaInset(edge: .bottom) {
                Button("Экспортировать выбранные") {
                    onExport(selection)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selection.isEmpty)
                .accessibilityIdentifier("exportSelectedCards")
                .padding()
            }
            .navigationTitle("Выбор карточек")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }

    private var selectionList: some View {
        let list = List(selection: $selection) {
            ForEach(cards) { card in
                Text(card.question)
            }
        }
        #if os(macOS)
        return list
        #else
        return list.environment(\.editMode, .constant(.active))
        #endif
    }
}
