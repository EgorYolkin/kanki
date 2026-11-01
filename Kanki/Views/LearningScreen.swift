import SwiftUI

struct LearningScreen: View {
    @State private var cards: [SessionCard] = []
    @State private var log = SessionLog()
    @State private var isAddingCard = false
    @State private var isReviewing = false
    @State private var selectedCard: SessionCard?

    var body: some View {
        List {
            Section {
                Text("Карточки и оценки сохраняются только до закрытия приложения. Расписание повторения и синхронизация пока недоступны.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if cards.isEmpty {
                Section {
                    SectionIntro(
                        symbol: "rectangle.stack",
                        title: "Карточек пока нет",
                        detail: "Добавьте карточку с вопросом и ответом для просмотра в этом сеансе."
                    )
                        .frame(maxWidth: .infinity)
                }
            } else {
                Section {
                    Text("Оценок в этом сеансе: \(log.count)")
                        .foregroundStyle(.secondary)
                    if let lastRating = log.lastRating {
                        Text("Последняя оценка: \(lastRating.title)")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Карточки этого сеанса") {
                    ForEach(cards) { card in
                        Button {
                            selectedCard = card
                        } label: {
                            Label(card.question, systemImage: "rectangle.on.rectangle")
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }

            Section {
                Button {
                    isReviewing = true
                } label: {
                    Label("Начать повторение", systemImage: "play.fill")
                }
                .accessibilityIdentifier("startReviewSession")
                .disabled(cards.isEmpty)
            } footer: {
                Text(cards.isEmpty
                     ? "Добавьте хотя бы одну карточку, чтобы начать сеанс."
                     : "Очередь пройдёт по карточкам этого сеанса. Расписание повторения не рассчитывается.")
            }
        }
        .navigationTitle("Обучение")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAddingCard = true
                } label: {
                    Label("Добавить карточку", systemImage: "plus")
                }
                .accessibilityIdentifier("addSessionCard")
            }
        }
        .sheet(isPresented: $isAddingCard) {
            AddSessionCardScreen { question, answer in
                cards.append(SessionCard(question: question, answer: answer))
            }
        }
        .sheet(item: $selectedCard) { card in
            SessionCardScreen(card: card) { rating in
                log.record(card, rating: rating)
            }
        }
        .sheet(isPresented: $isReviewing) {
            ReviewSessionScreen(cards: cards) { card, rating in
                log.record(card, rating: rating)
            }
        }
    }
}
