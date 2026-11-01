import SwiftUI

struct SettingsScreen: View {
    @AppStorage("appearance") private var appearance: AppAppearance = .system

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        List {
            Section("Оформление") {
                ForEach(AppAppearance.allCases) { option in
                    Button {
                        appearance = option
                    } label: {
                        HStack {
                            Text(option.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            if appearance == option {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .accessibilityIdentifier("appearance-\(option.rawValue)")
                    .accessibilityAddTraits(appearance == option ? [.isSelected] : [])
                }
                Text("Тема сохраняется между запусками и применяется ко всему приложению.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Синхронизация") {
                Label("Сервер не подключён", systemImage: "icloud.slash")
                    .foregroundStyle(.secondary)
                Text("Подключение, обмен с сервером и прогресс Anki появятся после этапа синхронизации.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Данные") {
                Text("Карточки и оценки хранятся на этом устройстве. Сервер не подключён, синхронизация не настроена.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Служебные экраны") {
                NavigationLink(value: Destination.merges) {
                    Label("Очередь мержей", systemImage: Destination.merges.symbol)
                }
                NavigationLink(value: Destination.conflicts) {
                    Label("Конфликты", systemImage: Destination.conflicts.symbol)
                }
            }
            Section("О приложении") {
                LabeledContent("Версия", value: appVersion)
                LabeledContent("Сборка", value: buildNumber)
                Text("Пробная сборка: импорт заметок, SRS и синхронизация ещё не реализованы.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Настройки")
    }
}
