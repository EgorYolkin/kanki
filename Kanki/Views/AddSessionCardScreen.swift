import SwiftUI

struct AddSessionCardScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = CardDraft()
    @State private var saveError = ""
    @State private var showSaveError = false
    @State private var selectedDeck: String?

    let availableDecks: [String]
    let initialDeck: String?
    let onAdd: (String, String, String?) throws -> Void

    init(
        availableDecks: [String],
        initialDeck: String? = nil,
        onAdd: @escaping (String, String, String?) throws -> Void
    ) {
        self.availableDecks = availableDecks
        self.initialDeck = initialDeck
        self.onAdd = onAdd
        _selectedDeck = State(initialValue: initialDeck)
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
                    }
                    .accessibilityIdentifier("cardDeckPicker")
                }
            }
            .navigationTitle("Карточка")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") {
                        if let card = draft.makeCard() {
                            do {
                                try onAdd(card.question, card.answer, selectedDeck)
                                dismiss()
                            } catch {
                                saveError = error.localizedDescription
                                showSaveError = true
                            }
                        }
                    }
                    .disabled(!draft.canSubmit)
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
