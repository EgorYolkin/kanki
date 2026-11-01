import SwiftUI

@main
struct KankiApp: App {
    @AppStorage("appearance") private var appearance: AppAppearance = .system

    init() {
        if ProcessInfo.processInfo.arguments.contains(LocalCardStore.resetArgument) {
            LocalCardStore.reset()
        }
    }

    var body: some Scene {
        WindowGroup {
            AppShell()
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
    var body: some View {
        TabView {
            NavigationStack {
                LearningScreen()
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
    var title: String {
        switch self {
        case .again: "Снова"
        case .hard: "Трудно"
        case .good: "Хорошо"
        case .easy: "Легко"
        }
    }

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
    @State private var cards: [SessionCard]
    @State private var reviews: [SessionReview]
    @State private var storageError: String?
    @State private var isAddingCard = false
    @State private var isReviewing = false
    @State private var selectedCard: SessionCard?

    init() {
        var snapshot = LearningSnapshot()
        var loadMessage: String?
        do {
            snapshot = try LocalCardStore.load()
        } catch {
            loadMessage = "Не удалось прочитать сохранённые карточки: \(error.localizedDescription)"
        }
        _cards = State(initialValue: snapshot.cards)
        _reviews = State(initialValue: snapshot.reviews)
        _storageError = State(initialValue: loadMessage)
    }

    var body: some View {
        List {
            if cards.isEmpty {
                Section {
                    SectionIntro(symbol: "rectangle.stack", title: "Карточек пока нет", detail: "Добавьте карточку с вопросом и ответом.")
                        .frame(maxWidth: .infinity)
                }
            } else {
                Section {
                    Text("Оценок: \(reviews.count)")
                        .foregroundStyle(.secondary)
                    if let lastReview = reviews.last {
                        Text("Последняя оценка: \(lastReview.rating.title)")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Карточки") {
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
        }
        .contentMargins(.bottom, 88, for: .scrollContent)
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
        .overlay(alignment: .bottomTrailing) {
            reviewButton
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
                reviews.append(SessionReview(cardID: card.id, rating: rating, reviewedAt: Date()))
                persist()
            }
        }
        .sheet(isPresented: $isReviewing) {
            ReviewSessionScreen(cards: cards) { card, rating in
                reviews.append(SessionReview(cardID: card.id, rating: rating, reviewedAt: Date()))
                persist()
            }
        }
        .alert("Ошибка сохранения", isPresented: isStorageErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(storageError ?? "")
        }
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
        .background { ReviewFloatingBackground() }
        .accessibilityLabel("Начать повторение")
        .accessibilityIdentifier("startReviewSession")
        .disabled(cards.isEmpty)
        .animation(.easeInOut(duration: 0.2), value: cards.isEmpty)
    }

    private var isStorageErrorPresented: Binding<Bool> {
        Binding(
            get: { storageError != nil },
            set: { if !$0 { storageError = nil } }
        )
    }

    private func persist() {
        do {
            try LocalCardStore.save(LearningSnapshot(cards: cards, reviews: reviews))
        } catch {
            storageError = "Не удалось сохранить данные: \(error.localizedDescription)"
        }
    }
}

private struct ReviewFloatingBackground: View {
    var body: some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .frame(width: 56, height: 56)
                .glassEffect(.regular.interactive(), in: Circle())
        } else {
            Circle()
                .fill(.regularMaterial)
                .frame(width: 56, height: 56)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.08)))
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        }
    }
}

private struct AddSessionCardScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var answer = ""

    let onAdd: (String, String) -> Void

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
                    Text("Карточка сохранится на этом iPhone.")
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
                        onAdd(question.trimmingCharacters(in: .whitespacesAndNewlines),
                              answer.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct SessionCardScreen: View {
    let card: SessionCard
    @State private var isAnswerVisible = false
    @State private var didSubmitRating = false
    @Environment(\.dismiss) private var dismiss
    let onReview: (RecallRating) -> Void

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
                                    onReview(rating)
                                    dismiss()
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
    }

}

private struct ReviewSessionScreen: View {
    let cards: [SessionCard]
    let onReview: (SessionCard, RecallRating) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var isAnswerVisible = false
    @State private var counts: [RecallRating: Int] = [:]

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
                Button("Готово") { dismiss() }
                    .accessibilityIdentifier("reviewFinish")
            }
        }
    }

    private func record(_ rating: RecallRating, for card: SessionCard) {
        counts[rating, default: 0] += 1
        onReview(card, rating)
        isAnswerVisible = false
        index += 1
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
                Text("Карточки и оценки хранятся на этом iPhone. Сервер не подключён, синхронизация не настроена.")
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
