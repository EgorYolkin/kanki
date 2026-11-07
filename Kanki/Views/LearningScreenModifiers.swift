import SwiftUI

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
