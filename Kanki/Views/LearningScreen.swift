import SwiftUI

struct LearningScreen: View {
    @State private var cards: [SessionCard]
    @State private var log: SessionLog
    @State private var loadError: String?
    @State private var isAddingCard = false
    @State private var isReviewing = false
    @State private var selectedCard: SessionCard?
    @State private var searchQuery = ""
    @State private var isChoosingCards = false
    @State private var exportDocument: CardExportDocument?
    @State private var isExporting = false
    @State private var pendingSelectedExport = false
    @State private var exportError: String?

    private var filteredCards: [SessionCard] {
        CardSearch.filter(cards, matching: searchQuery)
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
        _loadError = State(initialValue: loadMessage)
    }

    var body: some View {
        List {
            Section {
                Text("Карточки и оценки хранятся на этом устройстве. Расписание повторения и синхронизация пока недоступны.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let loadError {
                Section("Не удалось открыть карточки") {
                    Text(loadError)
                    Button("Повторить чтение") { reload() }
                }
            } else if cards.isEmpty {
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
                                Label(card.question, systemImage: "rectangle.on.rectangle")
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
        }
        .contentMargins(.bottom, 160, for: .scrollContent)
        .navigationTitle("Обучение")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Выбрать карточки") { isChoosingCards = true }
                    Button("Экспортировать все") {
                        exportDocument = CardExportDocument(archive: CardExportArchive(snapshot: snapshot))
                        isExporting = true
                    }
                } label: {
                    Label("Экспорт", systemImage: "square.and.arrow.up")
                }
                .disabled(loadError != nil || cards.isEmpty)
                .accessibilityIdentifier("cardExportMenu")
            }
        }
        .searchable(text: $searchQuery, prompt: "Поиск по карточкам")
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
                try addCard(question: question, answer: answer)
            }
        }
        .sheet(item: $selectedCard) { card in
            SessionCardScreen(card: card, history: log.history(for: card.id)) { rating in
                try record(card, rating: rating)
            }
        }
        .sheet(isPresented: $isReviewing) {
            ReviewSessionScreen(cards: cards) { card, rating in
                try record(card, rating: rating)
            }
        }
        .sheet(
            isPresented: $isChoosingCards,
            onDismiss: {
                if pendingSelectedExport {
                    pendingSelectedExport = false
                    isExporting = true
                }
            },
            content: {
                CardExportScreen(cards: cards) { selection in
                    exportDocument = CardExportDocument(
                        archive: CardExportArchive(snapshot: snapshot, selectedIDs: selection)
                    )
                    pendingSelectedExport = true
                }
            }
        )
        .fileExporter(isPresented: $isExporting,
                      document: exportDocument,
                      contentType: .json,
                      defaultFilename: "kanki-cards") { result in
            if case .failure(let error) = result,
               (error as? CocoaError)?.code != .userCancelled {
                exportError = error.localizedDescription
            }
        }
        .alert("Не удалось экспортировать", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("Закрыть", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
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
        .disabled(loadError != nil)
    }

    private var reviewButton: some View {
        Button {
            isReviewing = true
        } label: {
            Image(systemName: "play.fill")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(loadError != nil || cards.isEmpty ? Color.secondary : Color.primary)
                .frame(width: 56, height: 56)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background { FloatingCircleBackground(size: 56) }
        .accessibilityLabel("Начать повторение")
        .accessibilityIdentifier("startReviewSession")
        .disabled(loadError != nil || cards.isEmpty)
        .animation(.easeInOut(duration: 0.2), value: cards.isEmpty)
    }

    private var snapshot: LearningSnapshot {
        LearningSnapshot(cards: cards, reviews: log.reviews)
    }

    private func reload() {
        do {
            let snapshot = try LocalCardStore.load()
            cards = snapshot.cards
            log = SessionLog(reviews: snapshot.reviews)
            loadError = nil
        } catch {
            loadError = "Не удалось прочитать сохранённые карточки: \(error.localizedDescription)"
        }
    }

    private func addCard(question: String, answer: String) throws {
        cards.append(SessionCard(question: question, answer: answer))
        do {
            try LocalCardStore.save(snapshot)
        } catch {
            cards.removeLast()
            throw error
        }
    }

    private func record(_ card: SessionCard, rating: RecallRating) throws {
        log.record(card, rating: rating)
        do {
            try LocalCardStore.save(snapshot)
        } catch {
            log.discardLastRecord()
            throw error
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
