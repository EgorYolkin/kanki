import SwiftUI
import UniformTypeIdentifiers

struct CardExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let archive: CardArchive

    init(archive: CardArchive) {
        self.archive = archive
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        archive = try CardArchive.decode(data)
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
            List(selection: $selection) {
                ForEach(cards) { card in
                    Text(card.question)
                }
            }
            .environment(\.editMode, .constant(.active))
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }
}
