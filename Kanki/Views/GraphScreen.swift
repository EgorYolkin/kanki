import SwiftUI

struct GraphScreen: View {
    let uid: String
    @State private var note: Result<ImportedNote?, Error>?

    var body: some View {
        List {
            switch note {
            case .success(.some(let detail)):
                graph(detail)
            case .success(nil):
                SectionIntro(symbol: "doc", title: "Заметка не импортирована", detail: uid)
            case .failure:
                SectionIntro(symbol: "exclamationmark.triangle", title: "Не удалось прочитать граф", detail: "Откройте его ещё раз.")
            case nil:
                ProgressView()
            }
        }
        .navigationTitle("Граф заметки")
        .toolbarTitleDisplayMode(.inline)
        .task {
            let result = await Task.detached { [uid] in Result { try LocalCardStore.importedNote(uid) } }.value
            if !Task.isCancelled { note = result }
        }
    }

    private func graph(_ detail: ImportedNote) -> some View {
        let neighbors = detail.neighbors
        return Section("Ближайшие связи") {
            NavigationLink(value: ImportedNoteRoute.note(uid)) {
                Label(detail.summary.title, systemImage: "circle.fill").font(.headline)
            }
            .accessibilityIdentifier("graphCenter-\(uid)")
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            if neighbors.isEmpty {
                Text("У заметки нет связей.").foregroundStyle(.secondary)
            }
            ForEach(neighbors) { neighbor in
                neighborRow(neighbor)
                    .padding(.leading, 44)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .leading) {
                        branch(isLast: neighbor.id == neighbors.last?.id, isMissing: neighbor.title == nil)
                            .allowsHitTesting(false)
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }
        }
    }

    @ViewBuilder
    private func neighborRow(_ neighbor: ImportedNote.Neighbor) -> some View {
        let direction = direction(for: neighbor)
        if let title = neighbor.title {
            NavigationLink(value: ImportedNoteRoute.note(neighbor.id)) {
                neighborLabel(title, direction: direction)
            }
            .accessibilityIdentifier("graphNode-\(neighbor.id)")
        } else {
            neighborLabel("Не импортирована: \(neighbor.id)", direction: direction)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("graphMissing-\(neighbor.id)")
        }
    }

    private func neighborLabel(_ title: String, direction: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            Text(direction).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private func direction(for neighbor: ImportedNote.Neighbor) -> String {
        if neighbor.outgoing && neighbor.incoming { return "Входящая и исходящая связь" }
        return neighbor.outgoing ? "Исходящая связь" : "Входящая связь"
    }

    private func branch(isLast: Bool, isMissing: Bool) -> some View {
        Canvas { context, size in
            let mid = size.height / 2
            let stem = size.width / 4
            let tip = size.width - 4
            let trunk = Path { path in
                path.move(to: CGPoint(x: stem, y: 0))
                path.addLine(to: CGPoint(x: stem, y: isLast ? mid : size.height))
            }
            let branch = Path { path in
                path.move(to: CGPoint(x: stem, y: mid))
                path.addLine(to: CGPoint(x: tip, y: mid))
            }
            let node = Path(ellipseIn: CGRect(x: tip - 3, y: mid - 3, width: 6, height: 6))
            context.stroke(trunk, with: .color(.secondary), lineWidth: 1)
            context.stroke(branch, with: .color(.secondary), style: StrokeStyle(lineWidth: 1, dash: isMissing ? [3, 2] : []))
            if isMissing {
                context.stroke(node, with: .color(.secondary))
            } else {
                context.fill(node, with: .color(.accentColor))
            }
        }
        .frame(width: 32)
        .accessibilityHidden(true)
    }
}
