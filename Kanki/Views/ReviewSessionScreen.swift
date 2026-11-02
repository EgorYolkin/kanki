import SwiftUI

struct ReviewSessionScreen: View {
    let onReview: (SessionCard, RecallRating) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var session: ReviewSessionState
    @State private var saveError = ""
    @State private var showSaveError = false

    init(cards: [SessionCard], onReview: @escaping (SessionCard, RecallRating) throws -> Void) {
        self.onReview = onReview
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
            .navigationTitle("Повторение")
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
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("reviewProgress")
            }
            Section("Вопрос") {
                Text(card.question)
            }
            if session.isAnswerVisible {
                Section("Ответ") {
                    Text(card.answer)
                }
                Section("Насколько легко вспомнили?") {
                    HStack(spacing: 8) {
                        ForEach(RecallRating.allCases, id: \.self) { rating in
                            Button(rating.title) {
                                record(rating, for: card)
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(rating.tint, in: RoundedRectangle(cornerRadius: 10))
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                }
            } else {
                Section {
                    Button("Показать ответ") {
                        session.revealAnswer()
                    }
                }
            }
        }
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
            }
        }
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
