import SwiftUI

struct SessionCardFormScreen: View {
    /// Служебный тег пикера: включить ввод нового имени категории.
    private static let newDeckPlaceholder = "\u{1F}new-deck"

    private var newDeckPlaceholder: String { Self.newDeckPlaceholder }

    @Environment(\.dismiss) private var dismiss
    @State private var draft: CardDraft
    @State private var saveError = ""
    @State private var showSaveError = false
    @State private var savedCount = 0
    @State private var batchDecks: [String] = []

    /// Итоговая категория карточки: выбранная или введённая вручную.
    private var resolvedDeck: String? {
        CardCategory.trimmedDeck(isCreatingDeck ? newDeckName : selectedDeck)
    }

    private var deckNameError: String? {
        guard isCreatingDeck else { return nil }
        var existing: Set<String?> = Set(availableDecks)
        for deck in batchDecks { existing.insert(deck) }
        return CardCategory.validationError(for: newDeckName, existingDecks: existing)
    }

    private var canSubmit: Bool {
        draft.canSubmit && deckNameError == nil
    }

    private var canFinishWithoutSaving: Bool {
        lessonTitle != nil && savedCount > 0 && draft.isBlank
    }

    @State private var selectedDeck: String?
    @State private var isCreatingDeck = false
    @State private var newDeckName = ""

    let availableDecks: [String]
    let commitTitle: String
    private var lessonTitle: String?
    let onCommit: (String, String, String?) throws -> Void

    /// Создание одиночной карточки или редактирование существующей.
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

    init(
        availableDecks: [String],
        lessonTitle: String,
        onSave: @escaping (String, String, String?) throws -> Void
    ) {
        self.init(availableDecks: availableDecks, commitTitle: "Готово", onCommit: onSave)
        self.lessonTitle = lessonTitle
    }

    var body: some View {
        NavigationStack {
            Form {
                if let lessonTitle {
                    Section("Урок") {
                        Text(verbatim: lessonTitle)
                        Text("Добавлено: \(savedCount)")
                            .accessibilityIdentifier("lessonAddedCount")
                    }
                }
                CardTextEditorSection(title: "Вопрос", identifier: "cardQuestion", text: $draft.question)
                CardTextEditorSection(title: "Ответ", identifier: "cardAnswer", text: $draft.answer)
                Section("Категория") {
                    Picker("Категория", selection: $selectedDeck) {
                        Text(CardCategory.noCategoryTitle).tag(String?.none)
                        ForEach(availableDecks, id: \.self) { deck in
                            Text(deck).tag(String?.some(deck))
                        }
                        ForEach(batchDecks, id: \.self) { deck in
                            if !availableDecks.contains(deck) {
                                Text(deck).tag(String?.some(deck))
                            }
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
                if lessonTitle != nil {
                    Button("Сохранить и добавить ещё") { save(addingAnother: true) }
                        .disabled(!canSubmit)
                        .accessibilityIdentifier("cardSaveAndAdd")
                }
            }
            .navigationTitle("Карточка")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(commitTitle) { save(addingAnother: false) }
                        .disabled(!canSubmit && !canFinishWithoutSaving)
                        .accessibilityIdentifier(lessonTitle == nil ? commitTitle : "cardDone")
                }
            }
        }
        .alert("Не удалось сохранить карточку", isPresented: $showSaveError) {
            Button("Закрыть", role: .cancel) {}
        } message: {
            Text(saveError)
        }
    }

    private func save(addingAnother: Bool) {
        if !addingAnother && canFinishWithoutSaving {
            dismiss()
            return
        }
        guard canSubmit else { return }

        do {
            let deck = resolvedDeck
            try onCommit(draft.question, draft.answer, deck)
            if addingAnother {
                if isCreatingDeck, let deck {
                    if !batchDecks.contains(deck) { batchDecks.append(deck) }
                    selectedDeck = deck
                }
                savedCount += 1
                draft = CardDraft(deck: deck)
            } else {
                dismiss()
            }
        } catch {
            saveError = error.localizedDescription
            showSaveError = true
        }
    }
}
