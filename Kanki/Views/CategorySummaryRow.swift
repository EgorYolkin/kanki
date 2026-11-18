import SwiftUI

/// Строка категории в списке экрана «Обучение»: имя, счётчики «к повторению/всего»,
/// тап — обучение категории, long-press — контекстное меню.
/// Карточки служебной группы можно переместить или удалить с подтверждением.
struct CategorySummaryRow: View {
    let summary: CategorySummary
    let availableDecks: [String]
    let onStudy: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    /// Целевая категория; `nil` — «Без категории».
    let onMove: (String?) -> Void

    var body: some View {
        Button(action: onStudy) {
            HStack {
                Text(summary.title)
                    .foregroundStyle(Color.primary)
                Spacer()
                Text("\(summary.dueCount)/\(summary.totalCount)")
                    .foregroundStyle(Color.secondary)
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
            }
        }
        .contextMenu {
            if summary.deck != nil {
                Button("Переименовать…", action: onRename)
                Button("Удалить", role: .destructive, action: onDelete)
            } else {
                Button("Удалить все карточки", role: .destructive, action: onDelete)
                    .accessibilityIdentifier("deleteUncategorizedCards")
            }
            moveMenu
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if summary.deck == nil {
                // Destructive скрывает строку сразу, но здесь удаление ещё не подтверждено.
                Button(action: onDelete) {
                    Label("Удалить все", systemImage: "trash")
                }
                .tint(.red)
                .accessibilityLabel("Удалить карточки без категории")
                .accessibilityIdentifier("deleteUncategorizedCards")
            }
        }
    }

    /// Меню перемещения всех карточек категории в другую существующую категорию.
    /// Прямая переприсвойка `card.deck` без записи rename-операции.
    private var moveMenu: some View {
        Menu("Переместить все карточки…") {
            ForEach(availableDecks.filter { $0 != summary.deck }, id: \.self) { deck in
                Button(deck) {
                    onMove(deck)
                }
            }
            if summary.deck != nil {
                Button(CardCategory.noCategoryTitle) {
                    onMove(nil)
                }
            }
        }
    }
}
