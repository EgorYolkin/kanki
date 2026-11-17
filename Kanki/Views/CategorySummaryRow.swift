import SwiftUI

/// Строка категории в списке экрана «Обучение»: имя, счётчики «к повторению/всего»,
/// тап — обучение категории, long-press — контекстное меню.
/// Служебная строка «Без категории» ограничена перемещением карточек.
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
            HStack(spacing: 14) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 44, height: 44)
                    .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityHidden(true)
                Text(summary.title)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(summary.dueCount)/\(summary.totalCount)")
                    .foregroundStyle(.secondary)
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
            }
            .padding(.vertical, 6)
        }
        .contextMenu {
            if summary.deck != nil {
                Button("Переименовать…", action: onRename)
                Button("Удалить", role: .destructive, action: onDelete)
            }
            moveMenu
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
