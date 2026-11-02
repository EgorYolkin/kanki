import SwiftUI

struct AddSessionCardScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = CardDraft()

    let onAdd: (String, String) -> Void

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
                Section {
                    Text("Карточка сохранится на этом устройстве и не попадает в Anki или на сервер.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                            onAdd(card.question, card.answer)
                        }
                        dismiss()
                    }
                    .disabled(!draft.canSubmit)
                }
            }
        }
    }
}
