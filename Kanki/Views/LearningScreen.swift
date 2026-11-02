import SwiftUI

struct LearningScreen: View {
    @State private var cards: [SessionCard]
    @State private var log: SessionLog
    @State private var loadError: String?
    @State private var isAddingCard = false
    @State private var isReviewing = false
    @AppStorage("serverRevision") private var serverRevision = 0
    @State private var selectedCard: SessionCard?
    @State private var searchQuery = ""
    @State private var pushTask: Task<Void, Never>?
    @State private var syncError: String?
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
        .onAppear(perform: reload)
        .task {
            await pullIfLocalEmpty()
        }
        .onReceive(NotificationCenter.default.publisher(for: .kankiSnapshotReloaded)) { _ in
            reload()
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
            selectedCard = nil
            loadError = nil
        } catch {
            loadError = "Не удалось прочитать сохранённые карточки: \(error.localizedDescription)"
        }
    }

    private func addCard(question: String, answer: String) throws {
        cards.append(SessionCard(question: question, answer: answer))
        do {
            try LocalCardStore.save(snapshot)
            schedulePush()
        } catch {
            cards.removeLast()
            throw error
        }
    }

    private func record(_ card: SessionCard, rating: RecallRating) throws {
        log.record(card, rating: rating)
        do {
            try LocalCardStore.save(snapshot)
            schedulePush()
        } catch {
            log.discardLastRecord()
            throw error
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
