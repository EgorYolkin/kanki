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
    @AppStorage("appearance") private var appearance: AppAppearance = .system
    @AppStorage("serverURL") private var serverURL = ""
    @AppStorage("serverRevision") private var serverRevision = 0

    @State private var serverToken = ""
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
            serverSection
            dataSection
            serviceSection
            aboutSection
        }
        .navigationTitle("Настройки")
        .onAppear(perform: loadToken)
        .onChange(of: serverURL) { _, _ in
            serverRevision = 0
        }
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
    }

    private var serverSection: some View {
        Section("Сервер") {
            TextField("http://100.x.y.z:8000", text: $serverURL)
                .autocorrectionDisabled()
                .noAutocapitalization()
                .accessibilityIdentifier("serverURL")
            SecureField("Токен", text: $serverToken)
                .autocorrectionDisabled()
                .noAutocapitalization()
                .accessibilityIdentifier("serverToken")
            Button("Проверить соединение") {
                Task { await checkServer() }
            }
            .disabled(isServerBusy)
            .accessibilityIdentifier("serverCheck")
            Text(serverStatus)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("serverStatus")
            Button("Отправить на сервер") {
                Task { await pushSnapshot() }
            }
            .disabled(isServerBusy)
            .accessibilityIdentifier("serverPush")
            Button("Загрузить с сервера") {
                isConfirmingPull = true
            }
            .disabled(isServerBusy)
            .accessibilityIdentifier("serverPull")
            Text("Снимок отправляется вручную. Автоматического мержа нет: при конфликте ревизий загрузите данные с сервера.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var dataSection: some View {
        Section("Данные") {
            Text(
                "Карточки и история оценок хранятся на этом устройстве; JSON-экспорт — в меню «Экспорт» раздела «Обучение». "
                    + "Копию можно вручную отправить на сервер."
            )
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var serviceSection: some View {
        Section("Служебные экраны") {
            NavigationLink(value: Destination.merges) {
                Label("Очередь мержей", systemImage: Destination.merges.symbol)
            }
            NavigationLink(value: Destination.conflicts) {
                Label("Конфликты", systemImage: Destination.conflicts.symbol)
            }
        }
    }

    private var aboutSection: some View {
        Section("О приложении") {
            LabeledContent("Версия", value: appVersion)
            LabeledContent("Сборка", value: buildNumber)
        }
    }

    private func loadToken() {
        guard serverToken.isEmpty else { return }
        do {
            serverToken = try ServerTokenStore.load() ?? ""
        } catch {
            serverStatus = message(for: error)
        }
    }

    private func makeClient(token: String) throws -> ServerClient {
        guard let configuration = ServerConfiguration(rawValue: serverURL) else {
            throw ServerInputError.invalidURL
        }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ServerInputError.missingToken
        }
        try ServerTokenStore.save(trimmed)
        return ServerClient(configuration: configuration, token: trimmed)
    }

    @MainActor
    private func checkServer() async {
        isServerBusy = true
        defer { isServerBusy = false }
        do {
            let token = serverToken.trimmingCharacters(in: .whitespacesAndNewlines)
            let client = try makeClient(token: token)
            try ServerTokenStore.save(token)
            let identity = try await client.identity()
            serverStatus = "Подключено: \(identity.label)"
        } catch {
            serverStatus = message(for: error)
        }
    }

    @MainActor
    private func pushSnapshot() async {
        isServerBusy = true
        defer { isServerBusy = false }
        do {
            let client = try makeClient(token: serverToken)
            let local = try LocalCardStore.load()
            let result = try await client.push(snapshot: local, baseRevision: serverRevision)
            serverRevision = result.revision
            serverStatus = "Отправлено, ревизия \(result.revision)"
        } catch {
            serverStatus = message(for: error)
        }
    }

    @MainActor
    private func pullSnapshot() async {
        isServerBusy = true
        defer { isServerBusy = false }
        do {
            let client = try makeClient(token: serverToken)
            let result = try await client.fetchSnapshot()
            guard let snapshot = result.data else {
                serverStatus = "На сервере пока нет снимка"
                return
            }
            try LocalCardStore.save(snapshot)
            serverRevision = result.revision
            NotificationCenter.default.post(name: .kankiSnapshotReloaded, object: nil)
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
