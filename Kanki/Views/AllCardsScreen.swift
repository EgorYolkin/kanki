import SwiftUI

/// Плоский список всех карточек с поиском и чипами-фильтрами по категории.
/// Открытие карточки делегируется экрану «Обучение» через `onOpen`.
struct AllCardsScreen: View {
    let cards: [SessionCard]
    let schedules: [UUID: CardSchedule]
    let clock: Date
    let onOpen: (SessionCard) -> Void
    /// Архивирование и возврат карточки; ошибки сохранения показываются алертом.
    let onSetArchived: (SessionCard, Bool) throws -> Void
    let onDelete: (SessionCard) throws -> Void

    @State private var searchQuery = ""
    /// `nil` — фильтр не выбран («Все»); внутренний `Optional` различает
    /// «Все» и «Без категории» при тапе по чипу без категории.
    @State private var selectedDeck: String??
    /// Показывать архивные карточки вместо активных.
    @State private var showsArchive = false
    @State private var cardPendingDeletion: SessionCard?
    @State private var saveError: String?

    private var scopeCards: [SessionCard] {
        CardCategory.cards(cards, archived: showsArchive)
    }

    private var hasArchivedCards: Bool {
        !CardCategory.cards(cards, archived: true).isEmpty
    }

    private var deckNames: [String] {
        CardCategory.deckNames(in: scopeCards)
    }

    private var filteredCards: [SessionCard] {
        let scoped: [SessionCard]
        if let deck = selectedDeck {
            // Архивные карточки уже отобраны `scopeCards`, повторно их не фильтруем.
            scoped = CardCategory.cards(scopeCards, inDeck: deck, includingArchived: true)
        } else {
            scoped = scopeCards
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
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            cardPendingDeletion = card
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                        .accessibilityIdentifier("deleteCardSwipe")
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            setArchived(card, !card.isArchived)
                        } label: {
                            if card.isArchived {
                                Label("Вернуть", systemImage: "tray.and.arrow.up")
                            } else {
                                Label("В архив", systemImage: "archivebox")
                            }
                        }
                        .tint(.orange)
                        .accessibilityIdentifier("archiveCardSwipe")
                    }
                }
            } header: {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        deckChip(title: "Все", value: nil)
                        ForEach(deckNames, id: \.self) { deck in
                            deckChip(title: deck, value: deck)
                        }
                        if hasArchivedCards || showsArchive {
                            archiveChip
                        }
                    }
                }
                .textCase(nil)
            }
        }
        .overlay {
            if filteredCards.isEmpty {
                SectionIntro(
                    symbol: showsArchive ? "archivebox" : "magnifyingglass",
                    title: showsArchive ? "Архив пуст" : "Ничего не найдено",
                    detail: showsArchive
                        ? "Смахните карточку вправо, чтобы вернуть её из архива."
                        : "Измените запрос или выберите другую категорию."
                )
            }
        }
        .navigationTitle("Все карточки")
        .toolbarTitleDisplayMode(.inline)
        .onChange(of: showsArchive) { _, _ in
            selectedDeck = nil
        }
        .alert("Удалить карточку и историю повторений?", isPresented: isConfirmingDeletion) {
            Button("Удалить карточку", role: .destructive) {
                guard let card = cardPendingDeletion else { return }
                cardPendingDeletion = nil
                do {
                    try onDelete(card)
                } catch {
                    saveError = error.localizedDescription
                }
            }
            Button("Отмена", role: .cancel) {
                cardPendingDeletion = nil
            }
        }
        .alert("Не удалось сохранить изменение", isPresented: isSaveErrorPresented) {
            Button("Закрыть", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        #if os(iOS)
        // На iOS 26 поиск по умолчанию сворачивается и не находится в иерархии,
        // пока экран не прокрутят; в drawer он виден сразу.
        .searchable(
            text: $searchQuery,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Поиск по карточкам"
        )
        #else
        .searchable(text: $searchQuery, prompt: "Поиск по карточкам")
        #endif
    }

    private var archiveChip: some View {
        Button {
            showsArchive.toggle()
        } label: {
            Label("Архив", systemImage: "archivebox")
                .font(.footnote.weight(showsArchive ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(showsArchive ? Color.orange.opacity(0.22) : Color.clear)
                )
                .overlay(
                    Capsule().strokeBorder(showsArchive ? Color.orange : Color.secondary.opacity(0.4))
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("archiveFilterChip")
        .accessibilityLabel("Фильтр: Архив")
    }

    private var isConfirmingDeletion: Binding<Bool> {
        Binding(
            get: { cardPendingDeletion != nil },
            set: { if !$0 { cardPendingDeletion = nil } }
        )
    }

    private var isSaveErrorPresented: Binding<Bool> {
        Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )
    }

    private func setArchived(_ card: SessionCard, _ archived: Bool) {
        do {
            try onSetArchived(card, archived)
        } catch {
            saveError = error.localizedDescription
        }
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
        if card.isArchived {
            return "В архиве"
        }
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
