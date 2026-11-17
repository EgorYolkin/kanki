import SwiftUI

struct SessionCardScreen: View {
    /// Отображаемая копия: после правки или смены категории обновляется локально,
    /// не полагаясь на повторное создание sheet с тем же идентификатором.
    @State private var displayedCard: SessionCard
    let history: [SessionReview]
    @State private var isAnswerVisible = false
    @State private var didSubmitRating = false
    @State private var saveError = ""
    @State private var showSaveError = false
    @State private var isConfirmingDeletion = false
    @State private var isEditing = false
    @Environment(\.dismiss) private var dismiss
    let availableDecks: [String]
    let onReview: (RecallRating) throws -> Void
    /// Смена категории возвращает обновлённую карточку (или `nil`, если ничего не изменилось).
    let onChangeDeck: (String?) throws -> SessionCard?
    /// Сохранение правки вопроса, ответа и категории.
    let onUpdate: (String, String, String?) throws -> SessionCard?
    let onDelete: () throws -> Void

    init(
        card: SessionCard,
        history: [SessionReview],
        availableDecks: [String],
        onReview: @escaping (RecallRating) throws -> Void,
        onChangeDeck: @escaping (String?) throws -> SessionCard?,
        onUpdate: @escaping (String, String, String?) throws -> SessionCard?,
        onDelete: @escaping () throws -> Void
    ) {
        _displayedCard = State(initialValue: card)
        self.history = history
        self.availableDecks = availableDecks
        self.onReview = onReview
        self.onChangeDeck = onChangeDeck
        self.onUpdate = onUpdate
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Menu {
                        ForEach(availableDecks, id: \.self) { deck in
                            Button {
                                changeDeck(to: deck)
                            } label: {
                                if deck == displayedCard.deck {
                                    Label(deck, systemImage: "checkmark")
                                } else {
                                    Text(deck)
                                }
                            }
                        }
                        Button {
                            changeDeck(to: nil)
                        } label: {
                            if displayedCard.deck == nil {
                                Label(CardCategory.noCategoryTitle, systemImage: "checkmark")
                            } else {
                                Text(CardCategory.noCategoryTitle)
                            }
                        }
                    } label: {
                        Label(displayedCard.deck ?? CardCategory.noCategoryTitle, systemImage: "folder")
                            .font(.caption)
                    }
                    .accessibilityIdentifier("cardDeckChip")
                }
                 Section("Вопрос") {
                    Text(displayedCard.question)
                 }
                if isAnswerVisible {
                    Section("Ответ") {
                        Text(displayedCard.answer)
                    }
                } else {
                    Button("Показать ответ") {
                        isAnswerVisible = true
                    }
                }
                if isAnswerVisible {
                    Section("Насколько легко вспомнили?") {
                        HStack(spacing: 8) {
                            ForEach(RecallRating.allCases, id: \.self) { rating in
                                Button {
                                    guard !didSubmitRating else { return }
                                    didSubmitRating = true
                                    do {
                                        try onReview(rating)
                                        dismiss()
                                    } catch {
                                        didSubmitRating = false
                                        saveError = error.localizedDescription
                                        showSaveError = true
                                    }
                                } label: {
                                    Text(rating.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(rating.tint, in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                    }
                }
                Section("История повторений") {
                    if history.isEmpty {
                        Text("Оценок пока нет")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(history.indices, id: \.self) { index in
                            let review = history[index]
                            LabeledContent(review.rating.title,
                                           value: review.reviewedAt.formatted(.dateTime.locale(Locale.current)))
                        }
                    }
                }
                Section {
                    Button("Удалить карточку", role: .destructive) {
                        isConfirmingDeletion = true
                    }
                    .accessibilityIdentifier("deleteSessionCard")
                }
            }
            .navigationTitle("Карточка")
            .toolbarTitleDisplayMode(.inline)
            .onAppear {
                isAnswerVisible = false
                didSubmitRating = false
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Изменить") {
                        isEditing = true
                    }
                    .accessibilityIdentifier("editSessionCard")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .sheet(isPresented: $isEditing) {
                SessionCardFormScreen(
                    availableDecks: availableDecks,
                    draft: CardDraft(card: displayedCard),
                    commitTitle: "Сохранить"
                ) { question, answer, deck in
                    if let updated = try onUpdate(question, answer, deck) {
                        displayedCard = updated
                    }
                }
            }
        }
        .alert("Удалить карточку и историю повторений?", isPresented: $isConfirmingDeletion) {
            Button("Удалить карточку", role: .destructive) {
                do {
                    try onDelete()
                    dismiss()
                } catch {
                    saveError = error.localizedDescription
                    showSaveError = true
                }
            }
            Button("Отмена", role: .cancel) {}
        }
        .alert("Не удалось сохранить изменение", isPresented: $showSaveError) {
            Button("Закрыть", role: .cancel) {}
        } message: {
            Text(saveError)
        }
    }

    private func changeDeck(to deck: String?) {
        guard deck != displayedCard.deck else { return }
        do {
            if let updated = try onChangeDeck(deck) {
                displayedCard = updated
            }
        } catch {
            saveError = error.localizedDescription
            showSaveError = true
        }
    }
}
