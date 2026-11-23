import SwiftUI
import UniformTypeIdentifiers

struct ImportedCardsScreen: View {
    @Environment(\.importRevision) private var importRevision
    @State private var cards: [ImportedCardSummary] = []
    @State private var showsPicker = false
    @State private var isImporting = false
    @State private var loadError: String?
    @State private var importError: String?

    var body: some View {
        List {
            Section {
                Button("Импортировать .apkg", systemImage: "square.and.arrow.down") { showsPicker = true }
                    .accessibilityIdentifier("importAnkiPackage")
                    .disabled(isImporting)
                if isImporting { ProgressView("Импорт пакета…") }
            } footer: {
                Text("Карточки и оценки хранятся на этом устройстве. Прогресс Anki не переносится.")
            }
            if let loadError {
                Section {
                    Text(loadError)
                    Button("Повторить чтение", systemImage: "arrow.clockwise", action: reload)
                }
            } else if cards.isEmpty {
                SectionIntro(symbol: "tray", title: "Нет импортированных карточек", detail: "Выберите пакет .apkg профиля Kanki v1.")
            } else {
                NavigationLink(value: ImportedNoteRoute.library) {
                    Label("Библиотека заметок", systemImage: "books.vertical")
                }
                .accessibilityIdentifier("importedNoteLibrary")
                ForEach(cards) { card in
                    NavigationLink {
                        ImportedCardScreen(key: card.id)
                    } label: {
                        Label(AnkiFieldText.title(card.title), systemImage: "rectangle.on.rectangle")
                    }
                    .accessibilityIdentifier("importedCard-\(card.guid)")
                }
            }
        }
        .navigationTitle("Импортированные карточки")
        .toolbarTitleDisplayMode(.inline)
        .task(id: importRevision) { reload() }
        .fileImporter(isPresented: $showsPicker, allowedContentTypes: [.ankiPackage]) { result in
            Task { await importPackage(result) }
        }
        .alert("Не удалось импортировать пакет", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("Закрыть", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private func reload() {
        do {
            cards = try LocalCardStore.importedCards()
            loadError = nil
        } catch {
            loadError = "Не удалось открыть импортированные карточки: \(error.localizedDescription)"
        }
    }

    private func importPackage(_ result: Result<URL, Error>) async {
        isImporting = true
        defer { isImporting = false }
        do {
            let url = try result.get()
            try await Task.detached(priority: .userInitiated) { try LocalCardStore.importAnkiPackage(at: url) }.value
        } catch let error as AnkiPackageImport.PackageError {
            importError = error.localizedDescription
        } catch let error as CocoaError where error.code == .userCancelled {
            return
        } catch {
            importError = "Не удалось прочитать пакет или сохранить карточки. Сохранённые карточки не изменились."
        }
    }
}

private extension UTType {
    static let ankiPackage = UTType(filenameExtension: "apkg") ?? UTType(importedAs: "app.kanki.anki-package", conformingTo: .data)
}

struct ImportedCardPresentation {
    let detail: ImportedCardDetail
    let html: ImportedCardHTML
    var page: ImportedCardPage

    init(_ detail: ImportedCardDetail, replacing previous: Self? = nil) throws {
        self.detail = detail
        if let previous, previous.detail.content == detail.content {
            html = previous.html
            page = previous.detail.schedule == detail.schedule ? previous.page : ImportedCardPage(.question)
        } else {
            html = try ImportedCardHTML(content: detail.content)
            page = ImportedCardPage(.question)
        }
    }
}

private struct ImportedCardScreen: View {
    @Environment(\.importRevision) private var importRevision
    let key: AnkiE1Import.CardKey
    @State private var card: ImportedCardPresentation?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 12) {
            if let card {
                ImportedCardWebView(html: card.page.side == .answer ? card.html.revealed : card.html.question, pageID: card.page.id) { id, status in
                    self.card?.page.update(id: id, status: status)
                }
                .opacity(card.page.status == .ready ? 1 : 0)
                .accessibilityHidden(card.page.status != .ready)
                .accessibilityIdentifier("importedCardContent")
                .frame(minHeight: 160)
                if let schedule = card.detail.schedule {
                    LabeledContent("Следующий показ") {
                        Text(schedule.due, format: .dateTime.day().month().year().hour().minute().second())
                            .accessibilityIdentifier("importedCardDue")
                    }
                    NavigationLink {
                        history(card.detail.reviews)
                    } label: {
                        Label("История повторений", systemImage: "clock.arrow.circlepath")
                    }
                    .accessibilityIdentifier("importedCardHistory")
                }
                reviewControls(card)
            } else if error == nil {
                ProgressView()
            } else {
                Button("Повторить чтение", systemImage: "arrow.clockwise", action: reload)
            }
            if let error {
                Text(error).foregroundStyle(.red)
            }
        }
        .padding()
        .navigationTitle(card?.html.title ?? "Карточка")
        .toolbarTitleDisplayMode(.inline)
        .task(id: importRevision) { reload() }
        .onDisappear { card?.page = ImportedCardPage(.question) }
    }

    @ViewBuilder
    private func reviewControls(_ card: ImportedCardPresentation) -> some View {
        switch card.page.status {
        case .loading:
            ProgressView("Загрузка карточки…")
        case .failed:
            Text("Не удалось показать карточку.").foregroundStyle(.red)
            Button("Повторить показ") { request(card.page.side, replacing: card.page.id) }
        case .ready where card.page.side == .question:
            Button("Показать ответ") { request(.answer, replacing: card.page.id) }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("revealImportedAnswer")
        case .ready:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if card.detail.canReview(at: context.date) {
                    ratingButtons(card)
                }
            }
        }
    }

    private func history(_ reviews: [ImportedCardReview]) -> some View {
        List(reviews) { review in
            LabeledContent(review.rating.title) {
                Text(review.reviewedAt, format: .dateTime.day().month().year().hour().minute().second())
            }
        }
        .navigationTitle("История повторений")
        .toolbarTitleDisplayMode(.inline)
    }

    private func ratingButtons(_ card: ImportedCardPresentation) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack { ratings(card) }
            VStack { ratings(card) }
        }
        .buttonStyle(.bordered)
    }

    private func ratings(_ card: ImportedCardPresentation) -> some View {
        ForEach(RecallRating.allCases, id: \.self) { rating in
            Button(rating.title) { record(rating, shown: card) }
                .tint(rating.tint)
                .accessibilityIdentifier("importedRating-\(rating.rawValue)")
        }
    }

    private func request(_ side: ImportedCardPage.Side, replacing id: UUID) {
        guard card?.page.id == id else { return }
        card?.page = ImportedCardPage(side)
    }

    private func reload() {
        do {
            card = try ImportedCardPresentation(LocalCardStore.importedCard(key), replacing: card)
            error = nil
        } catch {
            card = nil
            self.error = "Не удалось открыть карточку: \(error.localizedDescription)"
        }
    }

    private func record(_ rating: RecallRating, shown: ImportedCardPresentation) {
        guard card?.page.id == shown.page.id, card?.page.canRate == true else { return }

        do {
            let updated = try LocalCardStore.recordImportedReview(key, shown: shown.detail, rating: rating, at: .now)
            card = try ImportedCardPresentation(updated, replacing: shown)
            ServerClient.scheduleActivityUpload()
            error = nil
        } catch {
            reload()
            if card != nil {
                self.error = "Не удалось сохранить оценку: \(error.localizedDescription)"
            }
        }
    }
}
