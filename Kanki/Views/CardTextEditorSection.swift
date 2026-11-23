import SwiftUI

struct CardTextEditorSection: View {
    let title: String
    let systemImage: String
    let identifier: String
    @Binding var text: String

    var body: some View {
        Section {
            TextEditor(text: $text)
                .frame(minHeight: 72)
                .accessibilityLabel(title)
                .accessibilityIdentifier(identifier)
            if text.range(of: #"\n"#, options: .literal) != nil {
                NavigationLink {
                    NewlineCorrectionScreen(title: title, source: text) { text = $0 }
                } label: {
                    Label("Исправить переносы…", systemImage: "return")
                }
                .accessibilityIdentifier(identifier + "Repair")
            }
        } header: {
            Label(title, systemImage: systemImage)
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
            Section {
                Text(verbatim: correction.source)
            } header: {
                Label("Исходный текст", systemImage: "doc.text")
            }
            Section {
                Button("Выбрать все", systemImage: "checkmark.circle") { correction.selected = Set(correction.matches.map(\.id)) }
                    .accessibilityIdentifier("newlineSelectAll")
                ForEach(correction.matches) { match in
                    Toggle(isOn: selection(for: match.id)) {
                        Text(verbatim: "\(match.id + 1). \(match.context)")
                    }
                    .accessibilityIdentifier("newlineMatch\(match.id)")
                }
            } header: {
                Label("Какие переносы исправить?", systemImage: "return")
            }
            Section {
                Text(verbatim: correction.preview)
                    .accessibilityIdentifier("newlinePreview")
            } header: {
                Label("Предпросмотр", systemImage: "eye")
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
