import SwiftUI

/// Модификатор экспорта карточек: sheet выбора, fileExporter и алерт ошибок.
/// Состояние остаётся у `LearningScreen`; модификатор только собирает UI.
struct CardExportFlowModifier: ViewModifier {
    @Binding var isChoosingCards: Bool
    @Binding var isExporting: Bool
    @Binding var pendingSelectedExport: Bool
    @Binding var exportDocument: CardExportDocument?
    @Binding var exportError: String?
    let cards: [SessionCard]
    let makeArchive: (Set<UUID>?) -> CardExportArchive

    func body(content: Content) -> some View {
        content
            .sheet(
                isPresented: $isChoosingCards,
                onDismiss: {
                    if pendingSelectedExport {
                        pendingSelectedExport = false
                        isExporting = true
                    }
                },
                content: {
                    CardExportScreen(cards: cards) { selection in
                        exportDocument = CardExportDocument(
                            archive: makeArchive(selection)
                        )
                        pendingSelectedExport = true
                    }
                }
            )
            .fileExporter(isPresented: $isExporting,
                          document: exportDocument,
                          contentType: .json,
                          defaultFilename: "kanki-cards") { result in
                if case .failure(let error) = result,
                   (error as? CocoaError)?.code != .userCancelled {
                    exportError = error.localizedDescription
                }
            }
            .alert("Не удалось экспортировать", isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button("Закрыть", role: .cancel) { exportError = nil }
            } message: {
                Text(exportError ?? "")
            }
    }
}

/// Алерты управления категориями: переименование и удаление с подтверждением.
struct DeckManagementAlertsModifier: ViewModifier {
    @Binding var renamingDeck: String?
    @Binding var renameText: String
    @Binding var renameError: String?
    @Binding var deckToDelete: CategorySummary?
    let onRename: (String, String) -> Void
    let onDelete: (String) -> Void

    func body(content: Content) -> some View {
        content
            .alert(
                "Переименовать категорию",
                isPresented: Binding(
                    get: { renamingDeck != nil },
                    set: { if !$0 { renamingDeck = nil } }
                )
            ) {
                TextField("Новое имя", text: $renameText)
                Button("Переименовать") {
                    if let deck = renamingDeck {
                        onRename(deck, renameText)
                    }
                }
                Button("Отмена", role: .cancel) {
                    renamingDeck = nil
                }
            } message: {
                Text(renamingDeck ?? "")
            }
            .alert("Не удалось переименовать", isPresented: Binding(
                get: { renameError != nil },
                set: { if !$0 { renameError = nil } }
            )) {
                Button("Закрыть", role: .cancel) { renameError = nil }
            } message: {
                Text(renameError ?? "")
            }
            .alert(
                "Удалить категорию?",
                isPresented: Binding(
                    get: { deckToDelete != nil },
                    set: { if !$0 { deckToDelete = nil } }
                )
            ) {
                Button("Удалить", role: .destructive) {
                    if let summary = deckToDelete, let deck = summary.deck {
                        onDelete(deck)
                    }
                }
                Button("Отмена", role: .cancel) {
                    deckToDelete = nil
                }
            } message: {
                Text("Все карточки категории «\(deckToDelete?.title ?? "")» перейдут в «\(CardCategory.noCategoryTitle)».")
            }
    }
}
