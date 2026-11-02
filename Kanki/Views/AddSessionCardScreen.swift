import SwiftUI

struct AddSessionCardScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = CardDraft()
    @State private var saveError = ""
    @State private var showSaveError = false

    let onAdd: (String, String) throws -> Void

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
                                try onAdd(card.question, card.answer)
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
