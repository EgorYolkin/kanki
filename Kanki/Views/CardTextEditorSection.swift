import SwiftUI

struct CardTextEditorSection: View {
    let title: String
    let identifier: String
    @Binding var text: String

    var body: some View {
        Section(title) {
            TextEditor(text: $text)
                .frame(minHeight: 72)
                .accessibilityLabel(title)
                .accessibilityIdentifier(identifier)
            if text.range(of: #"\n"#, options: .literal) != nil {
                NavigationLink {
                    NewlineCorrectionScreen(title: title, source: text) { text = $0 }
                } label: {
                    Text("Исправить переносы…")
                }
                .accessibilityIdentifier(identifier + "Repair")
            }
        }
    }
}

private struct NewlineCorrectionScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var correction: NewlineCorrection
    let title: String
    let onApply: (String) -> Void

    init(title: String, source: String, onApply: @escaping (String) -> Void) {
        self.title = title
        self.onApply = onApply
        _correction = State(initialValue: NewlineCorrection(source: source))
    }

    var body: some View {
        List {
            Section("Исходный текст") { Text(verbatim: correction.source) }
            Section("Какие переносы исправить?") {
                Button("Выбрать все") { correction.selected = Set(correction.matches.map(\.id)) }
                    .accessibilityIdentifier("newlineSelectAll")
                ForEach(correction.matches) { match in
                    Toggle(isOn: selection(for: match.id)) {
                        Text(verbatim: "\(match.id + 1). \(match.context)")
                    }
                    .accessibilityIdentifier("newlineMatch\(match.id)")
                }
            }
            Section("Предпросмотр") {
                Text(verbatim: correction.preview)
                    .accessibilityIdentifier("newlinePreview")
            }
        }
        .navigationTitle("Переносы: \(title)")
        .toolbarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
                    .accessibilityIdentifier("newlineCancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Применить") {
                    onApply(correction.preview)
                    dismiss()
                }
                .disabled(correction.selected.isEmpty)
                .accessibilityIdentifier("newlineApply")
            }
        }
    }

    private func selection(for id: Int) -> Binding<Bool> {
        Binding {
            correction.selected.contains(id)
        } set: { isSelected in
            if isSelected {
                correction.selected.insert(id)
            } else {
                correction.selected.remove(id)
            }
        }
    }
}
