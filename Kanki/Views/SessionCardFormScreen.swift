import SwiftUI

struct SessionCardFormScreen: View {
    /// Служебный тег пикера: включить ввод нового имени категории.
    private static let newDeckPlaceholder = "\u{1F}new-deck"

    private var newDeckPlaceholder: String { Self.newDeckPlaceholder }

    @Environment(\.dismiss) private var dismiss
    @State private var draft: CardDraft
    @State private var saveError = ""
    @State private var showSaveError = false

    /// Итоговая категория карточки: выбранная или введённая вручную.
    private var resolvedDeck: String? {
        CardCategory.trimmedDeck(isCreatingDeck ? newDeckName : selectedDeck)
    }

    private var deckNameError: String? {
        guard isCreatingDeck else { return nil }
        return CardCategory.validationError(for: newDeckName, existingDecks: Set(availableDecks))
    }

    private var canSubmit: Bool {
        draft.canSubmit && deckNameError == nil
    }
    @State private var selectedDeck: String?
    @State private var isCreatingDeck = false
    @State private var newDeckName = ""

    let availableDecks: [String]
    let commitTitle: String
    let onCommit: (String, String, String?) throws -> Void

    /// Форма работает в двух режимах: создание (`CardDraft()`) и редактирование
    /// (`CardDraft(card:)`); отличается только заголовок кнопки и исходные значения.
    init(
        availableDecks: [String],
        draft: CardDraft = CardDraft(),
        commitTitle: String = "Добавить",
        onCommit: @escaping (String, String, String?) throws -> Void
    ) {
        self.availableDecks = availableDecks
        self.commitTitle = commitTitle
        self.onCommit = onCommit
        _draft = State(initialValue: draft)
        _selectedDeck = State(initialValue: draft.deck)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Вопрос") {
                    TextField("Введите вопрос", text: $draft.question, axis: .vertical)
                        .lineLimit(2...5)
                        .accessibilityIdentifier("cardQuestion")
                }
                Section("Ответ") {
                    TextField("Введите ответ", text: $draft.answer, axis: .vertical)
                        .lineLimit(2...8)
                        .accessibilityIdentifier("cardAnswer")
                }
                Section("Категория") {
                    Picker("Категория", selection: $selectedDeck) {
                        Text(CardCategory.noCategoryTitle).tag(String?.none)
                        ForEach(availableDecks, id: \.self) { deck in
                            Text(deck).tag(String?.some(deck))
                        }
                        Text("Новая категория…").tag(String?.some(newDeckPlaceholder))
                    }
                    .accessibilityIdentifier("cardDeckPicker")
                    .onChange(of: selectedDeck) { _, deck in
                        isCreatingDeck = deck == newDeckPlaceholder
                        if !isCreatingDeck {
                            newDeckName = ""
                        }
                    }
                    if isCreatingDeck {
                        TextField("Имя категории", text: $newDeckName)
                            .accessibilityIdentifier("newDeckName")
                        if let deckNameError {
                            Text(deckNameError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("newDeckNameError")
                        }
                    }
                }
            }
            .navigationTitle("Карточка")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(commitTitle) {
                        guard let card = draft.makeCard() else { return }
                        do {
                            try onCommit(card.question, card.answer, resolvedDeck)
                            dismiss()
                        } catch {
                            saveError = error.localizedDescription
                            showSaveError = true
                        }
                    }
                    .disabled(!canSubmit)
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
