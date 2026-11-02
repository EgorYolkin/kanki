import Foundation
import SwiftUI

struct LearningScreen: View {
    @State private var cards: [SessionCard]
    @State private var log: SessionLog
    @State private var schedules: [UUID: CardSchedule]
    @State private var clock = Date()
    @State private var storageError: String?
    @State private var isAddingCard = false
    @State private var isReviewing = false
    @State private var selectedCard: SessionCard?
    @State private var searchQuery = ""

    private var filteredCards: [SessionCard] {
        CardSearch.filter(cards, matching: searchQuery)
    }

    private var dueCards: [SessionCard] {
        ReviewQueue.cards(cards, schedules: schedules, at: clock)
    }

    init() {
        var snapshot = LearningSnapshot()
        var loadMessage: String?
        do {
            snapshot = try LocalCardStore.load()
        } catch {
            loadMessage = "Не удалось прочитать сохранённые карточки: \(error.localizedDescription)"
        }
        _cards = State(initialValue: snapshot.cards)
        _log = State(initialValue: SessionLog(reviews: snapshot.reviews))
        _schedules = State(initialValue: snapshot.schedules)
        _storageError = State(initialValue: loadMessage)
    }

    var body: some View {
        List {
            if cards.isEmpty {
                Section {
                    SectionIntro(
                        symbol: "rectangle.stack",
                        title: "Карточек пока нет",
                        detail: "Добавьте карточку с вопросом и ответом кнопкой «плюс»."
                    )
                    .frame(maxWidth: .infinity)
                }
            } else {
                Section {
                    Text("К повторению: \(dueCards.count)")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("dueCount")
                    Text("Оценок: \(log.count)")
                        .foregroundStyle(.secondary)
                    if let lastRating = log.lastRating {
                        Text("Последняя оценка: \(lastRating.title)")
                            .foregroundStyle(.secondary)
                    }
                }

                if filteredCards.isEmpty {
                    Section {
                        SectionIntro(
                            symbol: "magnifyingglass",
                            title: "Ничего не найдено",
                            detail: "Измените запрос или добавьте новую карточку."
                        )
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    Section("Карточки") {
                        ForEach(filteredCards) { card in
                            Button {
                                selectedCard = card
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
                    }
                }
            }
        }
        .contentMargins(.bottom, 160, for: .scrollContent)
        .navigationTitle("Обучение")
        .searchable(text: $searchQuery, prompt: "Поиск по карточкам")
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                clock = Date()
            }
        }
        .overlay(alignment: .bottomTrailing) {
            VStack(alignment: .trailing, spacing: 12) {
                addCardButton
                reviewButton
            }
            .padding(.trailing, 20)
            .padding(.bottom, 20)
        }
        .sheet(isPresented: $isAddingCard) {
            AddSessionCardScreen { question, answer in
                cards.append(SessionCard(question: question, answer: answer))
                persist()
            }
        }
        .sheet(item: $selectedCard) { card in
            SessionCardScreen(card: card) { rating in
                record(card, rating: rating)
            }
        }
        .sheet(isPresented: $isReviewing) {
            ReviewSessionScreen(cards: dueCards) { card, rating in
                record(card, rating: rating)
            }
        }
        .alert("Ошибка сохранения", isPresented: isStorageErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(storageError ?? "")
        }
    }

    private var addCardButton: some View {
        Button {
            isAddingCard = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background { FloatingCircleBackground(size: 44) }
        .accessibilityLabel("Добавить карточку")
        .accessibilityIdentifier("addSessionCard")
    }

    private var reviewButton: some View {
        Button {
            isReviewing = true
        } label: {
            Image(systemName: "play.fill")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(dueCards.isEmpty ? Color.secondary : Color.primary)
                .frame(width: 56, height: 56)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background { FloatingCircleBackground(size: 56) }
        .accessibilityLabel("Начать повторение")
        .accessibilityIdentifier("startReviewSession")
        .disabled(dueCards.isEmpty)
        .animation(.easeInOut(duration: 0.2), value: dueCards.isEmpty)
    }

    private var isStorageErrorPresented: Binding<Bool> {
        Binding(
            get: { storageError != nil },
            set: { if !$0 { storageError = nil } }
        )
    }

    private func record(_ card: SessionCard, rating: RecallRating) {
        log.record(card, rating: rating)
        do {
            schedules[card.id] = try CardScheduling.nextReview(
                for: schedules[card.id],
                rating: rating,
                at: Date()
            )
        } catch {
            storageError = "Не удалось рассчитать следующий показ: \(error.localizedDescription)"
        }
        persist()
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
            formatter.locale = Locale(identifier: "ru_RU")
            formatter.unitsStyle = .full
            formatter.dateTimeStyle = .named
            return "Следующий показ: \(formatter.localizedString(for: date, relativeTo: clock))"
        }
    }

    private func persist() {
        do {
            let snapshot = LearningSnapshot(
                cards: cards,
                reviews: log.reviews,
                schedules: schedules
            )
            try LocalCardStore.save(snapshot)
        } catch {
            storageError = "Не удалось сохранить данные: \(error.localizedDescription)"
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
