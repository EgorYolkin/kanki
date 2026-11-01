#if os(macOS)
import SwiftUI

/// Меню «Раздел» в строке меню macOS: те же экраны доступны с клавиатуры
/// (⌘1–⌘4). Номера берутся из `AppSection.rawValue`.
struct SectionCommands: Commands {
    @Binding var section: AppSection

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Divider()
            Button(AppSection.learning.title) { section = .learning }
                .keyboardShortcut(shortcut(.learning), modifiers: .command)
            Button(AppSection.notes.title) { section = .notes }
                .keyboardShortcut(shortcut(.notes), modifiers: .command)
            Button(AppSection.graph.title) { section = .graph }
                .keyboardShortcut(shortcut(.graph), modifiers: .command)
            Button(AppSection.settings.title) { section = .settings }
                .keyboardShortcut(shortcut(.settings), modifiers: .command)
        }
    }

    private func shortcut(_ item: AppSection) -> KeyEquivalent {
        KeyEquivalent(Character(String(item.rawValue)))
    }
}
#endif
