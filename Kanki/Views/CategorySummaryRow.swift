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
            HStack {
                Text(summary.title)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(summary.dueCount)/\(summary.totalCount)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
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

struct FloatingCircleBackground: View {
    let size: CGFloat

    var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            Color.clear
                .frame(width: size, height: size)
                .glassEffect(.regular.interactive(), in: Circle())
        } else {
            Circle()
                .fill(.regularMaterial)
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.08)))
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        }
    }
}
