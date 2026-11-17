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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    deckMenu
                    VStack(alignment: .leading, spacing: 8) {
                        if !dynamicTypeSize.isAccessibilitySize {
                            Text("Вопрос")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        StudyText(text: displayedCard.question, isQuestion: true)
                    }
                    if isAnswerVisible {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Ответ")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            StudyText(text: displayedCard.answer)
                        }
                    }
                    Divider()
                    historySection
                    Button("Удалить карточку", role: .destructive) {
                        isConfirmingDeletion = true
                    }
                    .accessibilityIdentifier("deleteSessionCard")
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                reviewControls
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

    private var deckMenu: some View {
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
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("cardDeckChip")
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("История повторений")
                .font(.caption)
                .foregroundStyle(.secondary)
            if history.isEmpty {
                Text("Оценок пока нет")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(history.indices, id: \.self) { index in
                    let review = history[index]
                    LabeledContent(
                        review.rating.title,
                        value: review.reviewedAt.formatted(.dateTime.locale(Locale.current))
                    )
                }
            }
        }
    }

    private var reviewControls: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if isAnswerVisible {
                    if !dynamicTypeSize.isAccessibilitySize {
                        Text("Насколько легко вспомнили?")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    StudyRatingButtons(onRate: record)
                } else {
                    Button {
                        isAnswerVisible = true
                    } label: {
                        Text("Показать ответ")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .modifier(StudyActionStyle(prominent: true))
                }
            }
            .frame(maxWidth: 720)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
        }
        .background(.bar)
    }

    private func record(_ rating: RecallRating) {
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
