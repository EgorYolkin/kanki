import SwiftUI

/// Алерты управления категориями: переименование и удаление с подтверждением.
struct DeckManagementAlertsModifier: ViewModifier {
    @Binding var renamingDeck: String?
    @Binding var renameText: String
    @Binding var renameError: String?
    @Binding var deckToDelete: CategorySummary?
    let uncategorizedCardCount: Int
    let onRename: (String, String) -> Void
    let onDelete: (String) -> Void
    let onDeleteUncategorized: () -> Void

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
                deckToDelete?.deck == nil ? "Удалить карточки без категории?" : "Удалить категорию?",
                isPresented: Binding(
                    get: { deckToDelete != nil },
                    set: { if !$0 { deckToDelete = nil } }
                )
            ) {
                Button("Удалить", role: .destructive) {
                    guard let summary = deckToDelete else { return }
                    if let deck = summary.deck {
                        onDelete(deck)
                    } else {
                        onDeleteUncategorized()
                    }
                }
                Button("Отмена", role: .cancel) {
                    deckToDelete = nil
                }
            } message: {
                if deckToDelete?.deck == nil {
                    Text("Будут удалены все карточки без категории: \(uncategorizedCardCount), включая архивные, "
                         + "их оценки и расписания. Это действие нельзя отменить.")
                } else {
                    Text("Все карточки категории «\(deckToDelete?.title ?? "")» перейдут в «\(CardCategory.noCategoryTitle)».")
                }
            }
    }
}
