import SwiftUI

struct LearningScreen: View {
    @State private var cards: [SessionCard]
    @State private var log: SessionLog
    @State private var storageError: String?
    @State private var isAddingCard = false
    @State private var isReviewing = false
    @AppStorage("serverRevision") private var serverRevision = 0
    @State private var selectedCard: SessionCard?
    @State private var searchQuery = ""
    @State private var pushTask: Task<Void, Never>?
    @State private var syncError: String?

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
                cards.append(SessionCard(question: question, answer: answer))
                persist()
            }
        }
        .sheet(item: $selectedCard) { card in
            SessionCardScreen(card: card) { rating in
                log.record(card, rating: rating)
                persist()
            }
        }
        .sheet(isPresented: $isReviewing) {
            ReviewSessionScreen(cards: cards) { card, rating in
                log.record(card, rating: rating)
                persist()
            }
        }
        .onAppear(perform: reload)
        .task {
            await pullIfLocalEmpty()
        }
        .onReceive(NotificationCenter.default.publisher(for: .kankiSnapshotReloaded)) { _ in
            reload()
        }
        .alert("Ошибка сохранения", isPresented: isStorageErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(storageError ?? "")
        }
        .alert("Синхронизация", isPresented: isSyncErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(syncError ?? "")
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
                .foregroundStyle(cards.isEmpty ? Color.secondary : Color.primary)
                .frame(width: 56, height: 56)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background { FloatingCircleBackground(size: 56) }
        .accessibilityLabel("Начать повторение")
        .accessibilityIdentifier("startReviewSession")
        .disabled(cards.isEmpty)
        .animation(.easeInOut(duration: 0.2), value: cards.isEmpty)
    }

    private func reload() {
        do {
            let snapshot = try LocalCardStore.load()
            cards = snapshot.cards
            log = SessionLog(reviews: snapshot.reviews)
            selectedCard = nil
        } catch {
            storageError = "Не удалось прочитать сохранённые карточки: \(error.localizedDescription)"
        }
    }

    private var isStorageErrorPresented: Binding<Bool> {
        Binding(
            get: { storageError != nil },
            set: { if !$0 { storageError = nil } }
        )
    }

    private func persist() {
        do {
            try LocalCardStore.save(LearningSnapshot(cards: cards, reviews: log.reviews))
            schedulePush()
        } catch {
            storageError = "Не удалось сохранить данные: \(error.localizedDescription)"
        }
    }

    private var isSyncErrorPresented: Binding<Bool> {
        Binding(
            get: { syncError != nil },
            set: { if !$0 { syncError = nil } }
        )
    }

    private func serverClient() -> ServerClient? {
        guard let rawURL = UserDefaults.standard.string(forKey: "serverURL"),
              let configuration = ServerConfiguration(rawValue: rawURL)
        else {
            return nil
        }
        do {
            guard let stored = try ServerTokenStore.load() else { return nil }
            let token = stored.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { return nil }
            return ServerClient(configuration: configuration, token: token)
        } catch {
            return nil
        }
    }

    /// Отправляет снимок на сервер после локального изменения с коротким debounce.
    private func schedulePush() {
        guard let client = serverClient() else { return }
        let snapshot = LearningSnapshot(cards: cards, reviews: log.reviews)
        let baseRevision = serverRevision
        pushTask?.cancel()
        pushTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            do {
                let result = try await client.push(
                    snapshot: snapshot,
                    baseRevision: baseRevision
                )
                serverRevision = result.revision
            } catch let error as ServerError {
                if case .conflict(let current) = error {
                    syncError = "Конфликт ревизий: на сервере \(current). Загрузите снимок в настройках."
                }
            } catch {
                // Сеть недоступна; ручная синхронизация покажет ошибку.
            }
        }
    }

    /// Первый запуск на пустом устройстве подтягивает серверный снимок.
    private func pullIfLocalEmpty() async {
        guard cards.isEmpty, log.reviews.isEmpty, let client = serverClient() else { return }
        do {
            let remote = try await client.fetchSnapshot()
            guard let snapshot = remote.data else { return }
            try LocalCardStore.save(snapshot)
            serverRevision = remote.revision
            reload()
        } catch let error as ServerError {
            if case .conflict(let current) = error {
                syncError = "Конфликт ревизий: на сервере \(current)."
            }
        } catch {
            // Офлайн или сервер недоступен — локальные данные остаются.
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
