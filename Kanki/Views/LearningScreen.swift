import Foundation
import SwiftUI

struct LearningScreen: View {
    @State var cards: [SessionCard]
    @State var log: SessionLog
    @State var schedules: [UUID: CardSchedule]
    @State var deckRenames: [DeckRename]
    @State var clock = Date()
    @State var loadError: String?
    @State var isAddingCard = false
    @State var isReviewing = false
    @AppStorage("serverURL") var serverURL = ""
    @AppStorage("serverRevision") var serverRevision = 0
    @AppStorage("serverHasUnsyncedChanges") var hasUnsyncedChanges = false
    @Environment(\.scenePhase) private var scenePhase
    @State var selectedCard: SessionCard?
    @State var isReviewingDeck = false
    @State var selectedDeck: String?
    @State var renamingDeck: String?
    @State var renameText = ""
    @State var renameError: String?
    @State var deckToDelete: CategorySummary?
    @State var pushDebounceTask: Task<Void, Never>?
    @Binding var pushGate: PushGate
    @State var isReconciling = false
    @State var operationAlert: String?
    @Binding var syncProblem: SyncStatus.Problem?
    @State private var isChoosingCards = false
    @State private var exportDocument: CardExportDocument?
    @State private var isExporting = false
    @State private var pendingSelectedExport = false
    @State private var exportError: String?

    init(pushGate: Binding<PushGate>, syncProblem: Binding<SyncStatus.Problem?>) {
        _pushGate = pushGate
        _syncProblem = syncProblem
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
        _deckRenames = State(initialValue: snapshot.deckRenames)
        _loadError = State(initialValue: loadMessage)
    }

    var body: some View {
        // Читаем выбор в body: sheet не должен захватить предыдущую категорию.
        let categoryCards = isReviewingDeck ? deckReviewCards : []
        List {
            if let syncStatusText {
                Section {
                    Text(syncStatusText)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("syncStatus")
                }
            }
            NavigationLink {
                ImportedCardsScreen()
            } label: {
                Label("Импортированные карточки", systemImage: "tray.and.arrow.down")
            }
            .accessibilityIdentifier("importedCards")
            if let loadError {
                Section("Не удалось открыть карточки") {
                    Text(loadError)
                    Text("Чтобы заменить локальные карточки снимком сервера, подтвердите загрузку в настройках.")
                    Button("Повторить чтение") { reload() }
                }
            } else if cards.isEmpty {
                emptyCardsSection
            } else {
                categoriesSection
                uncategorizedSection
                allCardsSection
                statsSection
            }
        }
        .contentMargins(.bottom, 90, for: .scrollContent)
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
            SessionCardFormScreen(availableDecks: availableDecks) { question, answer, deck in
                try addCard(question: question, answer: answer, deck: deck)
            }
        }
        .sheet(item: $selectedCard) { card in
            SessionCardScreen(
                card: card,
                history: log.history(for: card.id),
                availableDecks: availableDecks,
                onReview: { rating in try record(card, rating: rating) },
                onChangeDeck: { newDeck in try changeDeck(of: card, to: newDeck) },
                onUpdate: { question, answer, deck in
                    try updateCard(card, question: question, answer: answer, deck: deck)
                },
                onDelete: { try deleteCard(card) }
            )
        }
        .sheet(isPresented: $isReviewing) {
            ReviewSessionScreen(
                cards: dueCards.isEmpty ? aheadCards : dueCards,
                isAheadReview: dueCards.isEmpty
            ) { card, rating in
                guard isReviewing else { throw CardReviewError.staleCard }
                try record(card, rating: rating)
            }
        }
        .sheet(isPresented: $isReviewingDeck) {
            ReviewSessionScreen(
                cards: categoryCards,
                isAheadReview: ReviewQueue.isAheadReview(categoryCards, schedules: schedules, at: clock)
            ) { card, rating in
                guard isReviewingDeck else { throw CardReviewError.staleCard }
                try record(card, rating: rating)
            }
        }
        .onAppear(perform: reload)
        .task {
            // Возврат из настроек не должен сразу подменить подтверждённый 409 новой сверкой.
            if case .conflict = syncProblem { return }
            await reconcile()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await reconcile() }
        }
        .onChange(of: pushGate.isManualSyncRunning) { _, isRunning in
            guard !isRunning, hasUnsyncedChanges else { return }
            schedulePush()
        }
        .onReceive(NotificationCenter.default.publisher(for: .kankiSnapshotReloaded)) { _ in
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .kankiCancelPendingPush)) { _ in
            pushDebounceTask?.cancel()
            pushDebounceTask = nil
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
        .alert("Синхронизация", isPresented: isOperationAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(operationAlert ?? "")
        }
        .modifier(
            DeckManagementAlertsModifier(
                renamingDeck: $renamingDeck,
                renameText: $renameText,
                renameError: $renameError,
                deckToDelete: $deckToDelete,
                onRename: { renameDeck(from: $0, to: $1) },
                onDelete: { deleteDeck($0) }
            )
        )
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
