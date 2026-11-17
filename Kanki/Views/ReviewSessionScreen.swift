import SwiftUI

struct ReviewSessionScreen: View {
    let onReview: (SessionCard, RecallRating) throws -> Void
    /// Заголовок сеанса: «Повторение» или «Досрочное повторение».
    private let title: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.progressText)
                        .monospacedDigit()
                        .accessibilityIdentifier("reviewProgress")
                    Text(card.deck ?? CardCategory.noCategoryTitle)
                        .accessibilityIdentifier("reviewDeck")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    if !dynamicTypeSize.isAccessibilitySize {
                        Text("Вопрос")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    StudyText(text: card.question, isQuestion: true)
                }
                if session.isAnswerVisible {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ответ")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        StudyText(text: card.answer)
                    }
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .id(card.id)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            reviewControls(for: card)
        }
    }

    private func reviewControls(for card: SessionCard) -> some View {
        VStack(spacing: 0) {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if session.isAnswerVisible {
                    if !dynamicTypeSize.isAccessibilitySize {
                        Text("Насколько легко вспомнили?")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    StudyRatingButtons { rating in
                        record(rating, for: card)
                    }
                } else {
                    Button {
                        session.revealAnswer()
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
