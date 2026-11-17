import SwiftUI

struct ReviewSessionScreen: View {
    let onReview: (SessionCard, RecallRating) throws -> Void
    /// Заголовок сеанса: «Повторение» или «Досрочное повторение».
    private let title: String

    @Environment(\.dismiss) private var dismiss
    @State private var session: ReviewSessionState
    @State private var saveError = ""
    @State private var showSaveError = false

    init(
        cards: [SessionCard],
        title: String = "Повторение",
        onReview: @escaping (SessionCard, RecallRating) throws -> Void
    ) {
        self.onReview = onReview
        self.title = title
        _session = State(initialValue: ReviewSessionState(cards: cards))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let currentCard = session.currentCard {
                    reviewView(for: currentCard)
                } else {
                    summaryView
                }
            }
            .navigationTitle(title)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .alert("Не удалось сохранить оценку", isPresented: $showSaveError) {
            Button("Закрыть", role: .cancel) {}
        } message: {
            Text(saveError)
        }
    }

    private func reviewView(for card: SessionCard) -> some View {
        List {
            Section {
                Text(session.progressText)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.tint)
                    .accessibilityIdentifier("reviewProgress")
                Text(card.deck ?? CardCategory.noCategoryTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("reviewDeck")
            }
            Section("Вопрос") {
                StudyText(text: card.question, isQuestion: true)
            }
            if session.isAnswerVisible {
                Section("Ответ") {
                    StudyText(text: card.answer)
                }
                Section("Насколько легко вспомнили?") {
                    StudyRatingButtons { rating in
                        record(rating, for: card)
                    }
                }
            } else {
                Section {
                    Button("Показать ответ") {
                        session.revealAnswer()
                    }
                    .controlSize(.large)
                    .modifier(StudyActionStyle(prominent: true))
                }
            }
        }
        .modifier(StudyListStyle())
    }

    private var summaryView: some View {
        List {
            Section {
                SectionIntro(symbol: "checkmark.circle", title: "Сеанс завершён", detail: "Оценено карточек: \(session.reviewedCount).")
                    .frame(maxWidth: .infinity)
            }
            Section("Оценки") {
                ForEach(session.summaryRows, id: \.rating) { row in
                    LabeledContent(row.rating.title, value: "\(row.count)")
                }
            }
            Section {
                Button("Готово") { dismiss() }
                    .accessibilityIdentifier("reviewFinish")
                    .controlSize(.large)
                    .modifier(StudyActionStyle(prominent: true))
            }
        }
        .modifier(StudyListStyle())
    }

    private func record(_ rating: RecallRating, for card: SessionCard) {
        guard session.currentCard?.id == card.id, session.isAnswerVisible else { return }
        do {
            try onReview(card, rating)
            _ = session.record(rating)
        } catch {
            saveError = error.localizedDescription
            showSaveError = true
        }
    }
}
