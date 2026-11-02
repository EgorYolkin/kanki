import SwiftUI

/// Плоский список всех карточек с поиском и чипами-фильтрами по категории.
/// Открытие карточки делегируется экрану «Обучение» через `onOpen`.
struct AllCardsScreen: View {
    let cards: [SessionCard]
    let schedules: [UUID: CardSchedule]
    let clock: Date
    let onOpen: (SessionCard) -> Void

    @State private var searchQuery = ""
    /// `nil` — фильтр не выбран («Все»); внутренний `Optional` различает
    /// «Все» и «Без категории» при тапе по чипу без категории.
    @State private var selectedDeck: String??

    private var deckNames: [String] {
        Array(Set(cards.compactMap(\.deck))).sorted()
    }

    private var filteredCards: [SessionCard] {
        let scoped: [SessionCard]
        if let deck = selectedDeck {
            scoped = CardCategory.cards(cards, inDeck: deck)
        } else {
            scoped = cards
        }
        return CardSearch.filter(scoped, matching: searchQuery)
    }

    var body: some View {
        List {
            Section {
                ForEach(filteredCards) { card in
                    Button {
                        onOpen(card)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(card.question, systemImage: "rectangle.on.rectangle")
                                .foregroundStyle(.primary)
                            Text(dueText(for: card))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel(card.question)
                }
            } header: {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        deckChip(title: "Все", value: nil)
                        ForEach(deckNames, id: \.self) { deck in
                            deckChip(title: deck, value: deck)
                        }
                    }
                }
                .textCase(nil)
            }
        }
        .overlay {
            if filteredCards.isEmpty {
                SectionIntro(
                    symbol: "magnifyingglass",
                    title: "Ничего не найдено",
                    detail: "Измените запрос или выберите другую категорию."
                )
            }
        }
        .navigationTitle("Все карточки")
        .toolbarTitleDisplayMode(.inline)
        .searchable(
            text: $searchQuery,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Поиск по карточкам"
        )
    }

    private func deckChip(title: String, value: String?) -> some View {
        let isSelected = value == nil ? selectedDeck == nil : selectedDeck == .some(value)
        return Button {
            selectedDeck = value == nil ? nil : .some(value)
        } label: {
            Text(title)
                .font(.footnote.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
                )
                .overlay(
                    Capsule().strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Фильтр: \(title)")
    }

    private func dueText(for card: SessionCard) -> String {
        guard let schedule = schedules[card.id] else {
            return "Новая — к повторению"
        }
        switch schedule.status(at: clock) {
        case .new:
            return "Новая — к повторению"
        case .due:
            return "Пора повторить"
        case .scheduled(let date):
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = Locale.current
            formatter.unitsStyle = .full
            formatter.dateTimeStyle = .named
            return "Следующий показ: \(formatter.localizedString(for: date, relativeTo: clock))"
        }
    }
}
