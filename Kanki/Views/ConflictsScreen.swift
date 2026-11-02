import SwiftUI

/// Экран «Конфликты»: журнал потерь категорий и ошибок синхронизации.
struct ConflictsScreen: View {
    @State private var entries: [String] = ConflictLog.entries()

    var body: some View {
        List {
            if entries.isEmpty {
                Section {
                    SectionIntro(
                        symbol: Destination.conflicts.symbol,
                        title: "Конфликтов нет",
                        detail: "Здесь появятся записи о потерянных категориях при загрузке с сервера."
                    )
                    .frame(maxWidth: .infinity)
                }
            } else {
                Section {
                    ForEach(entries, id: \.self) { entry in
                        Text(entry)
                    }
                }
            }
        }
        .navigationTitle("Конфликты")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Очистить") {
                    ConflictLog.clear()
                }
                .disabled(entries.isEmpty)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kankiConflictLogUpdated)) { _ in
            entries = ConflictLog.entries()
        }
    }
}
