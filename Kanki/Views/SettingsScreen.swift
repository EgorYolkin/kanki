import Foundation
import SwiftUI

private extension View {
    @ViewBuilder
    func noAutocapitalization() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
        #else
        self
        #endif
    }
}

private extension AppAppearance {
    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}

private enum ServerInputError: LocalizedError {
    case invalidURL
    case missingToken

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Укажите адрес вида http://100.x.y.z:8000"
        case .missingToken:
            "Укажите токен сервера"
        }
    }
}

struct SettingsScreen: View {
    @Binding var pushGate: PushGate
    @Binding var syncProblem: SyncStatus.Problem?
    @AppStorage("appearance") private var appearance: AppAppearance = .system
    @AppStorage("serverURL") private var serverURL = ""
    @AppStorage("serverRevision") private var serverRevision = 0
    @AppStorage("showNotesSection") private var showNotesSection = false
    @AppStorage("showGraphSection") private var showGraphSection = false
    @AppStorage("serverHasUnsyncedChanges") private var hasUnsyncedChanges = false

    @State private var draft = ServerSettingsDraft()
    @State private var serverStatus = "Не подключён"
    @State private var isServerBusy = false
    @State private var isConfirmingPull = false

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        List {
            appearanceSection
            sectionsSection
            serverSection
            dataSection
            aboutSection
        }
        .navigationTitle("Настройки")
        .onAppear(perform: loadDraft)
        .confirmationDialog(
            "Заменить локальные данные данными сервера?",
            isPresented: $isConfirmingPull,
            titleVisibility: .visible
        ) {
            Button("Заменить", role: .destructive) {
                Task { await pullSnapshot() }
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    private var appearanceSection: some View {
        Section {
            ForEach(AppAppearance.allCases) { option in
                Button {
                    appearance = option
                } label: {
                    HStack {
                        Label(option.title, systemImage: option.symbol)
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
        } header: {
            Label("Оформление", systemImage: "circle.lefthalf.filled")
        }
    }

    private var sectionsSection: some View {
        Section {
            Toggle(isOn: $showNotesSection) {
                Label("Заметки", systemImage: AppSection.notes.symbol)
            }
            .accessibilityIdentifier("showNotesSection")
            Toggle(isOn: $showGraphSection) {
                Label("Граф", systemImage: AppSection.graph.symbol)
            }
            .accessibilityIdentifier("showGraphSection")
            Text("Выберите, какие разделы показывать в панели вкладок.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Label("Разделы", systemImage: "square.grid.2x2")
        }
    }

    private var serverSection: some View {
        Section {
            TextField("http://100.x.y.z:8000", text: $draft.address)
                .disabled(isServerBusy)
                .autocorrectionDisabled()
                .noAutocapitalization()
                .accessibilityIdentifier("serverURL")
            SecureField("Токен", text: $draft.token)
                .disabled(isServerBusy)
                .autocorrectionDisabled()
                .noAutocapitalization()
                .accessibilityIdentifier("serverToken")
            Button("Проверить соединение", systemImage: "network") {
                Task { await checkServer() }
            }
            .disabled(isServerBusy)
            .accessibilityIdentifier("serverCheck")
            Text(serverStatus)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("serverStatus")
            Button("Отправить на сервер", systemImage: "arrow.up.circle") {
                Task { await pushSnapshot() }
            }
            .disabled(isServerBusy)
            .accessibilityIdentifier("serverPush")
            Button("Загрузить с сервера", systemImage: "arrow.down.circle") {
                isConfirmingPull = true
            }
            .disabled(isServerBusy)
            .accessibilityIdentifier("serverPull")
            if !serverURL.isEmpty {
                Button("Отключить сервер", systemImage: "xmark.circle", role: .destructive, action: disconnect)
                    .disabled(isServerBusy)
            }
            Text("Адрес и токен сохраняются при проверке соединения или обмене снимком.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("Снимок отправляется вручную. Автоматического мержа нет: при конфликте ревизий загрузите данные с сервера.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Label("Сервер", systemImage: "server.rack")
        }
    }

    private var dataSection: some View {
        Section {
            Text(
                "Карточки и история оценок хранятся на этом устройстве; JSON-экспорт — в меню «Экспорт» раздела «Обучение». "
                    + "Копию можно вручную отправить на сервер."
            )
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Label("Данные", systemImage: "internaldrive")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Версия", value: appVersion)
            LabeledContent("Сборка", value: buildNumber)
        } header: {
            Label("О приложении", systemImage: "info.circle")
        }
    }

    private func loadDraft() {
        do {
            let configuration = ServerTokenStore.configuration
            let token = try configuration.flatMap { try ServerTokenStore.load(for: $0) }
            draft = ServerSettingsDraft(address: configuration?.displayValue ?? "", token: token ?? "")
        } catch {
            serverStatus = message(for: error)
        }
    }

    private func commitDraft() throws -> ServerClient {
        guard let configuration = ServerConfiguration(rawValue: draft.address) else {
            throw ServerInputError.invalidURL
        }
        let trimmed = draft.token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ServerInputError.missingToken
        }
        let switching = configuration != ServerTokenStore.configuration
        try ServerTokenStore.commit(trimmed, for: configuration)
        if switching { resetSyncDestination() }
        return ServerClient(configuration: configuration, token: trimmed)
    }

    private func disconnect() {
        do {
            try ServerTokenStore.delete()
            resetSyncDestination()
            draft = ServerSettingsDraft()
            serverStatus = "Не подключён"
        } catch {
            serverStatus = message(for: error)
        }
    }

    private func resetSyncDestination() {
        serverRevision = 0
        syncProblem = nil
        pushGate.markChanged()
        NotificationCenter.default.post(name: .kankiCancelPendingPush, object: nil)
    }

    @MainActor
    private func checkServer() async {
        isServerBusy = true
        defer { isServerBusy = false }
        do {
            let client = try commitDraft()
            let identity = try await client.verifyDestination()
            serverStatus = "Подключено: \(identity.label)"
        } catch {
            serverStatus = message(for: error)
        }
    }

    @MainActor
    private func pushSnapshot() async {
        guard pushGate.beginManualSync() else {
            serverStatus = "Дождитесь завершения синхронизации и повторите."
            return
        }
        defer { pushGate.finishManualSync() }
        isServerBusy = true
        defer { isServerBusy = false }
        NotificationCenter.default.post(name: .kankiCancelPendingPush, object: nil)
        var attemptedClient: ServerClient?
        do {
            let client = try commitDraft()
            attemptedClient = client
            let local = try LocalCardStore.load()
            let generation = pushGate.generation
            let result = try await client.push(snapshot: local, baseRevision: serverRevision)
            guard client.usesCurrentCredentials else { return }
            serverRevision = result.revision
            if pushGate.isCurrent(generation) {
                hasUnsyncedChanges = false
            }
            syncProblem = nil
            serverStatus = "Отправлено, ревизия \(result.revision)"
        } catch {
            guard attemptedClient?.usesCurrentCredentials != false else { return }
            if case .conflict(let revision) = error as? ServerError {
                syncProblem = .conflict(currentRevision: revision)
            }
            serverStatus = message(for: error)
        }
    }

    @MainActor
    private func pullSnapshot() async {
        guard pushGate.beginManualSync() else {
            serverStatus = "Дождитесь завершения синхронизации и повторите."
            return
        }
        defer { pushGate.finishManualSync() }
        isServerBusy = true
        defer { isServerBusy = false }
        NotificationCenter.default.post(name: .kankiCancelPendingPush, object: nil)
        do {
            let client = try commitDraft()
            let generation = pushGate.generation
            let revision = serverRevision
            let result = try await client.fetchSnapshot()
            guard client.usesCurrentCredentials else { return }
            guard pushGate.isCurrent(generation), serverRevision == revision else {
                serverStatus = "Локальные данные изменились во время загрузки. Повторите загрузку."
                return
            }
            guard let snapshot = result.data else {
                serverStatus = "На сервере пока нет снимка"
                return
            }
            try LocalCardStore.replaceFromConfirmedPull(snapshot)
            serverRevision = result.revision
            hasUnsyncedChanges = false
            NotificationCenter.default.post(name: .kankiSnapshotReloaded, object: nil)
            syncProblem = nil
            serverStatus = "Загружено, ревизия \(result.revision)"
        } catch {
            serverStatus = message(for: error)
        }
    }

    private func message(for error: Error) -> String {
        if let serverError = error as? ServerError {
            switch serverError {
            case .invalidResponse:
                return "Сервер вернул некорректный ответ"
            case .unauthorized:
                return "Токен отклонён"
            case .conflict(let revision):
                return "Конфликт ревизий: на сервере \(revision). Загрузите снимок с сервера."
            case .http(let status):
                return "Ошибка сервера: \(status)"
            case .decoding:
                return "Сервер вернул неожиданные данные"
            }
        }
        if let urlError = error as? URLError {
            return "Не удалось связаться: \(urlError.localizedDescription)"
        }
        if let tokenError = error as? ServerTokenStoreError {
            return tokenError.localizedDescription
        }
        return error.localizedDescription
    }
}
