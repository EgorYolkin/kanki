#if os(macOS)
import SwiftUI

/// Меню «Раздел» в строке меню macOS: видимые разделы доступны с клавиатуры.
/// Номера берутся из `AppSection.rawValue` и стабильны: у скрытого раздела
/// сосед не занимается его номером (⌘1 «Обучение», ⌘4 «Настройки»).
struct SectionCommands: Commands {
    @Binding var section: AppSection
    @AppStorage("showNotesSection") private var showNotesSection = false
    @AppStorage("showGraphSection") private var showGraphSection = false

    private var visibleSections: [AppSection] {
        AppSection.visible(notesShown: showNotesSection, graphShown: showGraphSection)
    }

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Divider()
            ForEach(visibleSections, id: \.self) { item in
                Button(item.title) { section = item }
                    .keyboardShortcut(shortcut(item), modifiers: .command)
            }
        }
    }

    private func shortcut(_ item: AppSection) -> KeyEquivalent {
        KeyEquivalent(Character(String(item.rawValue)))
    }
}
#endif
