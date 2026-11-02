import SwiftUI

@main
struct KankiApp: App {
    @AppStorage("appearance") private var appearance: AppAppearance = .system
    @State private var library = CardLibrary()

    var body: some Scene {
        WindowGroup {
            AppShell(library: library)
                .tint(.indigo)
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}

private enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Системное"
        case .light: "Светлое"
        case .dark: "Тёмное"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum Destination: Hashable {
    case note, editor, search, library, merges, conflicts

    var title: String {
        switch self {
        case .note: "Заметка"
        case .editor: "Редактор заметки"
        case .library: "Библиотека"
        case .search: "Поиск"
        case .merges: "Очередь мержей"
        case .conflicts: "Конфликты"
        }
    }

    var symbol: String {
        switch self {
        case .note: "note.text"
        case .editor: "square.and.pencil"
        case .library: "books.vertical"
        case .merges: "arrow.triangle.merge"
        case .search: "magnifyingglass"
        case .conflicts: "exclamationmark.arrow.triangle.2.circlepath"
        }
    }
}

struct AppShell: View {
    let library: CardLibrary
    var body: some View {
        TabView {
            NavigationStack {
                LearningScreen(library: library)
                    .navigationDestination(for: Destination.self) { destination in
                        PlaceholderScreen(destination: destination)
                    }
            }
            .tabItem { Label("Обучение", systemImage: "rectangle.stack") }

            NavigationStack {
                NotesScreen()
                    .navigationDestination(for: Destination.self) { destination in
                        PlaceholderScreen(destination: destination)
                    }
            }
            .tabItem { Label("Заметки", systemImage: "note.text") }

            NavigationStack {
                GraphScreen()
            }
            .tabItem { Label("Граф", systemImage: "circle.hexagongrid") }

            NavigationStack {
                SettingsScreen()
                    .navigationDestination(for: Destination.self) { destination in
                        PlaceholderScreen(destination: destination)
                    }
            }
            .tabItem { Label("Настройки", systemImage: "gearshape") }
        }
    }
}

private struct SectionIntro: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(detail)
        }
    }
}

private extension RecallRating {
    var tint: Color {
        switch self {
        case .again: .red
        case .hard: .orange
        case .good: .green
        case .easy: .blue
        }
    }
}

private struct LearningScreen: View {
    let library: CardLibrary
    @State private var isAddingCard = false
    @State private var isReviewing = false
    @State private var isChoosingCards = false
    @State private var selectedCard: SessionCard?
    @State private var exportDocument: CardExportDocument?
    @State private var isExporting = false
    @State private var pendingSelectedExport = false
    @State private var exportError: String?

    var body: some View {
        List {
            Section {
                Text("Карточки и история оценок сохраняются на этом устройстве. Расписание повторения и синхронизация пока недоступны.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let loadError = library.loadError {
                Section("Не удалось открыть карточки") {
                    Text(loadError)
                    Button("Повторить чтение") { library.reload() }
                }
            } else if library.cards.isEmpty {
                Section {
                    SectionIntro(symbol: "rectangle.stack", title: "Карточек пока нет", detail: "Добавьте карточку с вопросом и ответом для хранения на этом устройстве.")
                        .frame(maxWidth: .infinity)
                }
            } else {
                Section {
                    Text("Всего оценок: \(library.reviews.count)")
                        .foregroundStyle(.secondary)
                    if let lastReview = library.reviews.last {
                        Text("Последняя оценка: \(lastReview.rating.title)")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Мои карточки") {
                    ForEach(library.cards) { card in
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
                .disabled(library.loadError != nil || library.cards.isEmpty)
            } footer: {
                Text(library.cards.isEmpty
                     ? "Добавьте хотя бы одну карточку, чтобы начать сеанс."
                     : "Очередь пройдёт по сохранённым карточкам. Расписание повторения не рассчитывается.")
            }
        }
        .navigationTitle("Обучение")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Выбрать карточки") { isChoosingCards = true }
                    Button("Экспортировать все") {
                        exportDocument = CardExportDocument(archive: library.export())
                        isExporting = true
                    }
                } label: {
                    Label("Экспорт", systemImage: "square.and.arrow.up")
                }
                .disabled(library.loadError != nil || library.cards.isEmpty)
                .accessibilityIdentifier("cardExportMenu")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAddingCard = true
                } label: {
                    Label("Добавить карточку", systemImage: "plus")
                }
                .disabled(library.loadError != nil)
                .accessibilityIdentifier("addSessionCard")
            }
        }
        .sheet(isPresented: $isAddingCard) {
            AddSessionCardScreen { question, answer in
                try library.add(question: question, answer: answer)
            }
        }
        .sheet(item: $selectedCard) { card in
            SessionCardScreen(card: card, history: library.history(for: card.id)) { rating in
                try library.record(card, rating: rating)
            }
        }
        .sheet(isPresented: $isReviewing) {
            ReviewSessionScreen(cards: library.cards) { card, rating in
                try library.record(card, rating: rating)
            }
        }
        .sheet(isPresented: $isChoosingCards, onDismiss: {
            if pendingSelectedExport {
                pendingSelectedExport = false
                isExporting = true
            }
        }) {
            CardExportScreen(cards: library.cards) { selection in
                exportDocument = CardExportDocument(archive: library.export(selectedIDs: selection))
                pendingSelectedExport = true
            }
        }
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
}

private struct AddSessionCardScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var answer = ""
    @State private var saveError = ""
    @State private var showSaveError = false

    let onAdd: (String, String) throws -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Вопрос") {
                    TextField("Введите вопрос", text: $question, axis: .vertical)
                        .lineLimit(2...5)
                        .accessibilityIdentifier("cardQuestion")
                }
                Section("Ответ") {
                    TextField("Введите ответ", text: $answer, axis: .vertical)
                        .lineLimit(2...8)
                        .accessibilityIdentifier("cardAnswer")
                }
                Section {
                    Text("Карточка сохранится на этом устройстве, но не попадёт в Anki или на сервер.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Карточка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") {
                        do {
                            try onAdd(question.trimmingCharacters(in: .whitespacesAndNewlines),
                                      answer.trimmingCharacters(in: .whitespacesAndNewlines))
                            dismiss()
                        } catch {
                            saveError = error.localizedDescription
                            showSaveError = true
                        }
                    }
                    .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .alert("Не удалось сохранить карточку", isPresented: $showSaveError) {
            Button("Закрыть", role: .cancel) {}
        } message: {
            Text(saveError)
        }
    }
}

private struct SessionCardScreen: View {
    let card: SessionCard
    let history: [SessionReview]
    @State private var isAnswerVisible = false
    @State private var didSubmitRating = false
    @State private var saveError = ""
    @State private var showSaveError = false
    @Environment(\.dismiss) private var dismiss
    let onReview: (RecallRating) throws -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Вопрос") {
                    Text(card.question)
                }
                if isAnswerVisible {
                    Section("Ответ") {
                        Text(card.answer)
                    }
                } else {
                    Button("Показать ответ") {
                        isAnswerVisible = true
                    }
                }
                if isAnswerVisible {
                    Section("Насколько легко вспомнили?") {
                        HStack(spacing: 8) {
                            ForEach(RecallRating.allCases, id: \.self) { rating in
                                Button {
                                    guard !didSubmitRating else { return }
                                    didSubmitRating = true
                                    do {
                                        try onReview(rating)
                                        dismiss()
                                    } catch {
                                        didSubmitRating = false
                                        saveError = error.localizedDescription
                                        showSaveError = true
                                    }
                                } label: {
                                    Text(rating.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(rating.tint, in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                    }
                }
                Section("История повторений") {
                    if history.isEmpty {
                        Text("Оценок пока нет")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(history) { review in
                            LabeledContent(review.rating.title,
                                           value: review.reviewedAt.formatted(date: .abbreviated, time: .standard))
                        }
                    }
                }
                Section {
                    Text("История сохраняется на устройстве. Срок следующего повтора не рассчитывается.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Карточка")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                isAnswerVisible = false
                didSubmitRating = false
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
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

}

private struct ReviewSessionScreen: View {
    let cards: [SessionCard]
    let onReview: (SessionCard, RecallRating) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var isAnswerVisible = false
    @State private var counts: [RecallRating: Int] = [:]
    @State private var saveError = ""
    @State private var showSaveError = false

    private var currentCard: SessionCard? {
        cards.indices.contains(index) ? cards[index] : nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if let currentCard {
                    reviewView(for: currentCard)
                } else {
                    summaryView
                }
            }
            .navigationTitle("Повторение")
            .navigationBarTitleDisplayMode(.inline)
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
        List {
            Section {
                Text("Карточка \(index + 1) из \(cards.count)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("reviewProgress")
            }
            Section("Вопрос") {
                Text(card.question)
            }
            if isAnswerVisible {
                Section("Ответ") {
                    Text(card.answer)
                }
                Section("Насколько легко вспомнили?") {
                    HStack(spacing: 8) {
                        ForEach(RecallRating.allCases, id: \.self) { rating in
                            Button(rating.title) {
                                record(rating, for: card)
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(rating.tint, in: RoundedRectangle(cornerRadius: 10))
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                }
            } else {
                Section {
                    Button("Показать ответ") {
                        isAnswerVisible = true
                    }
                }
            }
            Section {
                Text("Оценка сохранится на устройстве. Расписание повторения не рассчитывается.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var summaryView: some View {
        List {
            Section {
                SectionIntro(symbol: "checkmark.circle", title: "Сеанс завершён", detail: "Оценено карточек: \(counts.values.reduce(0, +)).")
                    .frame(maxWidth: .infinity)
            }
            Section("Оценки") {
                ForEach(RecallRating.allCases, id: \.self) { rating in
                    if let count = counts[rating], count > 0 {
                        LabeledContent(rating.title, value: "\(count)")
                    }
                }
            }
            Section {
                Text("История оценок сохранена на устройстве. Сроки и синхронизация пока не поддерживаются.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Готово") { dismiss() }
                    .accessibilityIdentifier("reviewFinish")
            }
        }
    }

    private func record(_ rating: RecallRating, for card: SessionCard) {
        do {
            try onReview(card, rating)
            counts[rating, default: 0] += 1
            isAnswerVisible = false
            index += 1
        } catch {
            saveError = error.localizedDescription
            showSaveError = true
        }
    }
}

private struct NotesScreen: View {
    var body: some View {
        List {
            Section {
                SectionIntro(symbol: "text.magnifyingglass", title: "Заметок пока нет", detail: "Поиск, связи и редактирование заработают после импорта данных.")
                    .frame(maxWidth: .infinity)
            }
            Section("Предпросмотр экранов") {
                NavigationLink(value: Destination.search) {
                    Label("Поиск", systemImage: Destination.search.symbol)
                }
                NavigationLink(value: Destination.note) {
                    Label("Экран заметки", systemImage: Destination.note.symbol)
                }
                NavigationLink(value: Destination.editor) {
                    Label("Редактор", systemImage: Destination.editor.symbol)
                }
                NavigationLink(value: Destination.library) {
                    Label("Библиотека", systemImage: Destination.library.symbol)
                }
            }
        }
        .navigationTitle("Заметки")
    }
}

private struct GraphScreen: View {
    var body: some View {
        SectionIntro(symbol: "circle.hexagongrid", title: "Граф пуст", detail: "После импорта здесь будут заметка и её ближайшие связи.")
            .navigationTitle("Граф")
    }
}

private struct SettingsScreen: View {
    @AppStorage("appearance") private var appearance: AppAppearance = .system

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        List {
            Section("Оформление") {
                Picker("Тема", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("appearancePicker")
                Text("Тема сохраняется между запусками и применяется ко всему приложению.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Синхронизация") {
                Label("Сервер не подключён", systemImage: "icloud.slash")
                    .foregroundStyle(.secondary)
                Text("Подключение, обмен с сервером и прогресс Anki появятся после этапа синхронизации.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Данные") {
                Text("Карточки и история оценок сохраняются на устройстве; JSON-экспорт доступен в меню «Экспорт» вкладки «Обучение». SRS и синхронизации нет.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Служебные экраны") {
                NavigationLink(value: Destination.merges) {
                    Label("Очередь мержей", systemImage: Destination.merges.symbol)
                }
                NavigationLink(value: Destination.conflicts) {
                    Label("Конфликты", systemImage: Destination.conflicts.symbol)
                }
            }
            Section("О приложении") {
                LabeledContent("Версия", value: appVersion)
                LabeledContent("Сборка", value: buildNumber)
                Text("Пробная сборка: импорт заметок, SRS и синхронизация ещё не реализованы.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Настройки")
    }
}

private struct PlaceholderScreen: View {
    let destination: Destination

    var body: some View {
        SectionIntro(symbol: destination.symbol, title: destination.title, detail: "Это заготовка экрана. Данные и действия появятся на следующих этапах.")
            .navigationTitle(destination.title)
            .navigationBarTitleDisplayMode(.inline)
    }
}
