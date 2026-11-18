import SwiftUI
import UniformTypeIdentifiers

struct ImportedCardsScreen: View {
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
                    Button("Повторить чтение", action: reload)
                }
            } else if cards.isEmpty {
                SectionIntro(symbol: "tray", title: "Нет импортированных карточек", detail: "Выберите пакет .apkg профиля Kanki v1.")
            } else {
                ForEach(cards) { card in
                    NavigationLink {
                        ImportedCardScreen(key: card.id)
                    } label: {
                        Text(ImportedCardHTML.displayTitle(card.title))
                    }
                    .accessibilityIdentifier("importedCard-\(card.guid)")
                }
            }
        }
        .navigationTitle("Импортированные карточки")
        .toolbarTitleDisplayMode(.inline)
        .task { reload() }
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
            reload()
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

private struct ImportedCardScreen: View {
    let key: AnkiE1Import.CardKey
    @State private var detail: ImportedCardDetail?
    @State private var html: ImportedCardHTML?
    @State private var isAnswerRevealed = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 12) {
            if let detail, let html {
                ImportedCardWebView(html: isAnswerRevealed ? html.revealed : html.question)
                    .accessibilityIdentifier("importedCardContent")
                    .frame(minHeight: 160)
                if let schedule = detail.schedule {
                    LabeledContent("Следующий показ") {
                        Text(schedule.due, format: .dateTime.day().month().year().hour().minute().second())
                            .accessibilityIdentifier("importedCardDue")
                    }
                    NavigationLink("История повторений") { history(detail.reviews) }
                        .accessibilityIdentifier("importedCardHistory")
                }
                if !isAnswerRevealed {
                    Button("Показать ответ") { isAnswerRevealed = true }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("revealImportedAnswer")
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if detail.canReview(at: context.date) {
                            ratingButtons(detail)
                        }
                    }
                }
            } else if error == nil {
                ProgressView()
            } else {
                Button("Повторить чтение", action: reload)
            }
            if let error {
                Text(error).foregroundStyle(.red)
            }
        }
        .padding()
        .navigationTitle(html?.title ?? "Карточка")
        .toolbarTitleDisplayMode(.inline)
        .task { reload() }
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

    private func ratingButtons(_ detail: ImportedCardDetail) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack { ratings(detail) }
            VStack { ratings(detail) }
        }
        .buttonStyle(.bordered)
    }

    private func ratings(_ detail: ImportedCardDetail) -> some View {
        ForEach(RecallRating.allCases, id: \.self) { rating in
            Button(rating.title) { record(rating, shown: detail) }
                .tint(rating.tint)
                .accessibilityIdentifier("importedRating-\(rating.rawValue)")
        }
    }

    private func reload() {
        do {
            let loaded = try LocalCardStore.importedCard(key)
            html = try ImportedCardHTML(content: loaded.content)
            detail = loaded
            isAnswerRevealed = false
            error = nil
        } catch {
            self.error = "Не удалось открыть карточку: \(error.localizedDescription)"
        }
    }

    private func record(_ rating: RecallRating, shown: ImportedCardDetail) {
        do {
            detail = try LocalCardStore.recordImportedReview(key, shown: shown, rating: rating, at: .now)
            isAnswerRevealed = false
            error = nil
        } catch {
            self.error = "Не удалось сохранить оценку: \(error.localizedDescription)"
        }
    }
}
