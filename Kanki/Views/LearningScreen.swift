import Foundation
import SwiftUI

struct LearningScreen: View {
    @State var snapshot: LearningSnapshot
    @State var localRead: SnapshotReadState
    @State var clock = Date()
    @State var isAddingCard = false
    @State var isCreatingLesson = false
    @State var selectedLessonID: UUID?
    @State var reviewAttempt: ReviewAttempt?
    @AppStorage("serverURL") var serverURL = ""
    @AppStorage("serverRevision") var serverRevision = 0
    @AppStorage("serverHasUnsyncedChanges") var hasUnsyncedChanges = false
    @Environment(\.scenePhase) private var scenePhase
    @State var selectedCard: SessionCard?
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
        _snapshot = State(initialValue: snapshot)
        _localRead = State(initialValue: SnapshotReadState(failure: loadMessage))
    }

    var body: some View {
        List {
            if let syncStatusText {
                Section {
                    Text(syncStatusText)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("syncStatus")
                }
            }
            NavigationLink(value: ImportedNoteRoute.cards) {
                Label("Импортированные карточки", systemImage: "tray.and.arrow.down")
            }
            .accessibilityIdentifier("importedCards")
            if let loadError = localRead.failure {
                Section("Не удалось открыть карточки") {
                    Text(loadError)
                    Text("Чтобы заменить локальные карточки снимком сервера, подтвердите загрузку в настройках.")
                    Button("Повторить чтение") { reload() }
                }
            } else {
                lessonHomeSection
                if snapshot.cards.isEmpty {
                    emptyCardsSection
                } else {
                    categoriesSection
                    uncategorizedSection
                    allCardsSection
                    statsSection
                }
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
                .disabled(!localRead.isReadable || snapshot.cards.isEmpty)
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
        .navigationDestination(item: $selectedLessonID) { lessonDestination($0) }
        .navigationDestination(for: LessonCatalogRoute.self) { lessonCatalogDestination($0) }
        .sheet(isPresented: $isCreatingLesson) { lessonCreationSheet }
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
                onReview: { displayedCard, rating in
                    guard selectedCard?.id == displayedCard.id else { throw CardReviewError.staleCard }
                    try record(displayedCard, rating: rating)
                },
                onChangeDeck: { newDeck in try changeDeck(of: card, to: newDeck) },
                onUpdate: { question, answer, deck in
                    try updateCard(card, question: question, answer: answer, deck: deck)
                },
                onDelete: { try deleteCard(card) }
            )
        }
        .sheet(item: $reviewAttempt) { attempt in
            ReviewSessionScreen(cards: attempt.cards, isAheadReview: attempt.isAhead, title: attempt.title) { card, rating in
                guard reviewAttempt?.id == attempt.id else { throw CardReviewError.staleCard }
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
                CardExportScreen(cards: snapshot.cards) { selection in
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
