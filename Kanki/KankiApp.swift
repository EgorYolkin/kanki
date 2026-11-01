import SwiftUI

@main
struct KankiApp: App {
    var body: some Scene {
        WindowGroup {
            AppShell()
                .tint(.indigo)
        }
    }
}

enum Destination: Hashable {
    case card, note, editor, search, library, merges, conflicts

    var title: String {
        switch self {
        case .card: "Карточка"
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
        case .card: "rectangle.on.rectangle"
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

private struct SessionCard: Identifiable {
    let id = UUID()
    let question: String
    let answer: String
}

private enum RecallRating: Int, CaseIterable {
    case again = 1
    case hard
    case good
    case easy

    var title: String {
        switch self {
        case .again: "Снова"
        case .hard: "Трудно"
        case .good: "Хорошо"
        case .easy: "Легко"
        }
    }
}

private struct SessionReview {
    let cardID: UUID
    let rating: RecallRating
    let reviewedAt: Date
}

private struct LearningScreen: View {
    @State private var cards: [SessionCard] = []
    @State private var reviews: [SessionReview] = []
    @State private var isAddingCard = false
    @State private var selectedCard: SessionCard?

    var body: some View {
        List {
            Section {
                Text("Карточки и оценки сохраняются только до закрытия приложения. Расписание повторения и синхронизация пока недоступны.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if cards.isEmpty {
                Section {
                    SectionIntro(symbol: "rectangle.stack", title: "Карточек пока нет", detail: "Добавьте карточку с вопросом и ответом для просмотра в этом сеансе.")
                        .frame(maxWidth: .infinity)
                }
            } else {
                Section {
                    Text("Оценок в этом сеансе: \(reviews.count)")
                        .foregroundStyle(.secondary)
                    if let lastReview = reviews.last {
                        Text("Последняя оценка: \(lastReview.rating.title)")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Карточки этого сеанса") {
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

            Section("Предпросмотр экранов") {
                NavigationLink(value: Destination.card) {
                    Label("Будущий экран повторения", systemImage: Destination.card.symbol)
                }
            }
        }
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
        .sheet(isPresented: $isAddingCard) {
            AddSessionCardScreen { question, answer in
                cards.append(SessionCard(question: question, answer: answer))
            }
        }
        .sheet(item: $selectedCard) { card in
            SessionCardScreen(card: card) { rating in
                reviews.append(SessionReview(cardID: card.id, rating: rating, reviewedAt: Date()))
            }
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
                    Text("Карточка доступна только в этом сеансе и не попадает в Anki или на сервер.")
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
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(RecallRating.allCases, id: \.self) { rating in
                                Button(rating.title) {
                                    guard !didSubmitRating else { return }
                                    didSubmitRating = true
                                    onReview(rating)
                                    dismiss()
                                }
                                .buttonStyle(.bordered)
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                Section {
                    Text("Оценка останется только в этом сеансе. Срок следующего повтора не рассчитывается.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Карточка этого сеанса")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
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
    var body: some View {
        List {
            Section("Синхронизация") {
                Label("Сервер не подключён", systemImage: "icloud.slash")
                    .foregroundStyle(.secondary)
            }
            Section("Предпросмотр экранов") {
                NavigationLink(value: Destination.merges) {
                    Label("Очередь мержей", systemImage: Destination.merges.symbol)
                }
                NavigationLink(value: Destination.conflicts) {
                    Label("Конфликты", systemImage: Destination.conflicts.symbol)
                }
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
