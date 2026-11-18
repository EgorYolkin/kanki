import SwiftUI

enum ImportedNoteRoute: Hashable {
    case cards
    case library
    case note(String)
    case graph(String)

    @MainActor
    @ViewBuilder
    var screen: some View {
        switch self {
        case .cards: ImportedCardsScreen()
        case .library: NotesScreen(mode: .library).toolbarTitleDisplayMode(.inline)
        case .note(let uid): ImportedNoteScreen(uid: uid)
        case .graph(let uid): GraphScreen(uid: uid)
        }
    }
}

struct NotesScreen: View {
    enum Mode {
        case notes
        case library
        case graph

        var title: String {
            switch self {
            case .notes: "Заметки"
            case .library: "Библиотека заметок"
            case .graph: "Граф"
            }
        }
    }

    var mode: Mode = .notes
    @Environment(\.importRevision) private var importRevision
    @State private var query = ""
    @State private var notes: Result<[ImportedNoteSummary], Error>?

    var body: some View {
        List {
            switch notes {
            case .success(let rows) where !rows.isEmpty:
                if mode == .graph {
                    Text("Выберите заметку, чтобы увидеть её ближайшие связи.")
                        .foregroundStyle(.secondary)
                }
                ForEach(rows) { note in
                    NavigationLink(value: mode == .graph ? ImportedNoteRoute.graph(note.uid) : .note(note.uid)) {
                        Text(note.title)
                    }
                    .accessibilityIdentifier("libraryNote-\(note.uid)")
                }
            case .success:
                emptyState
            case .failure:
                SectionIntro(symbol: "exclamationmark.triangle", title: "Не удалось прочитать заметки", detail: "Откройте раздел ещё раз.")
            case nil:
                ProgressView()
            }
        }
        .navigationTitle(mode.title)
        .searchable(text: $query, prompt: "Заголовок или текст")
        .task(id: SearchRequest(query: query, importRevision: importRevision)) {
            await loadNotes(matching: query)
        }
    }

    private struct SearchRequest: Equatable {
        let query: String
        let importRevision: Int
    }

    private var emptyState: some View {
        Group {
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                SectionIntro(symbol: "magnifyingglass", title: "Ничего не найдено", detail: "Попробуйте другие слова.")
            } else {
                SectionIntro(
                    symbol: mode == .graph ? "circle.hexagongrid" : "tray",
                    title: mode == .graph ? "Граф пуст" : "Заметок пока нет",
                    detail: "Импортируйте пакет .apkg в разделе «Обучение»."
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func loadNotes(matching query: String) async {
        if !query.isEmpty {
            do {
                try await Task.sleep(for: .milliseconds(150))
            } catch {
                return
            }
        }
        let result = await Task.detached { Result { try LocalCardStore.importedNotes(matching: query) } }.value
        if !Task.isCancelled { notes = result }
    }
}

struct ImportedNoteScreen: View {
    let uid: String
    @Environment(\.importRevision) private var importRevision
    @State private var note: Result<ImportedNote?, Error>?

    var body: some View {
        List {
            switch note {
            case .success(.some(let detail)):
                if !detail.body.isEmpty {
                    Text(detail.body)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("importedNoteBody")
                }
                NavigationLink("Граф заметки", value: ImportedNoteRoute.graph(uid))
                    .accessibilityIdentifier("openNoteGraph")
                links("Исходящие связи", detail.outgoing)
                links("Обратные ссылки", detail.backlinks)
            case .success(nil):
                SectionIntro(symbol: "doc", title: "Заметка не импортирована", detail: uid)
            case .failure:
                SectionIntro(symbol: "exclamationmark.triangle", title: "Не удалось прочитать заметку", detail: "Откройте её ещё раз.")
            case nil:
                ProgressView()
            }
        }
        .navigationTitle(title)
        .toolbarTitleDisplayMode(.inline)
        .task(id: importRevision) {
            let result = await Task.detached { [uid] in Result { try LocalCardStore.importedNote(uid) } }.value
            if !Task.isCancelled { note = result }
        }
    }

    private var title: String {
        if case .success(.some(let detail)) = note { return detail.summary.title }
        return "Заметка"
    }

    @ViewBuilder
    private func links(_ heading: String, _ links: [ImportedNoteLink]) -> some View {
        if !links.isEmpty {
            Section(heading) {
                ForEach(links) { link in
                    if let title = link.title {
                        NavigationLink(value: ImportedNoteRoute.note(link.uid)) { linkLabel(title, link) }
                            .accessibilityIdentifier("\(link.isBacklink ? "backlink" : "outgoing")-\(link.uid)-\(link.id.position)")
                    } else {
                        linkLabel("Не импортирована: \(link.uid)", link)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("missingNote-\(link.uid)-\(link.id.position)")
                    }
                }
            }
        }
    }

    private func linkLabel(_ title: String, _ link: ImportedNoteLink) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            Text(link.type).font(.footnote).foregroundStyle(.secondary)
            if let comment = link.comment, !comment.isEmpty {
                Text(comment).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
