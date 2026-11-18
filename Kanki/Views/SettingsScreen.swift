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

struct SettingsScreen: View {
    @Binding var pushGate: PushGate
    @Binding var syncProblem: SyncStatus.Problem?
    @AppStorage("appearance") private var appearance: AppAppearance = .system
    @AppStorage("snapshotServerURL") private var snapshotAddress = ""
    @AppStorage("deltaServerURL") private var deltaAddress = ""
    @AppStorage("serverRevision") private var serverRevision = 0
    @AppStorage("showNotesSection") private var showNotesSection = false
    @AppStorage("showGraphSection") private var showGraphSection = false
    @AppStorage("serverHasUnsyncedChanges") private var hasUnsyncedChanges = false

    @FocusState private var focusedToken: ServerTokenStore.Scope?
    @State private var snapshot = ServerCredentialDraft()
    @State private var delta = ServerCredentialDraft()
    @State private var snapshotStatus: String?
    @State private var deltaStatus: String?
    @State private var didLoadDrafts = false
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
            deltaSection
            dataSection
            aboutSection
        }
        .navigationTitle("Настройки")
        .onAppear(perform: loadDrafts)
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
}

private extension SettingsScreen {
    var appearanceSection: some View {
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

    var sectionsSection: some View {
        Section("Разделы") {
            Toggle("Заметки", isOn: $showNotesSection)
                .accessibilityIdentifier("showNotesSection")
            Toggle("Граф", isOn: $showGraphSection)
                .accessibilityIdentifier("showGraphSection")
            Text("Разделы «Заметки» и «Граф» пока заготовки; включите переключатель, чтобы вернуть раздел в панель вкладок.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    var serverSection: some View {
        Section("Снимок ручных карточек") {
            serverField("http://100.x.y.z:8000", id: "serverURL", text: snapshotField(\.address))
            tokenField(.snapshot, id: "serverToken", text: snapshotField(\.token))
            Button("Проверить соединение") { Task { await checkServer() } }
                .disabled(isServerBusy)
                .accessibilityIdentifier("serverCheck")
            Text(snapshotStatus ?? "Не подключён")
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
            Text("Адрес и токен вступают в силу при проверке, отправке или загрузке снимка.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("Автоматического мержа нет: при конфликте ревизий загрузите снимок с сервера.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    var deltaSection: some View {
        Section {
            serverField("https://kanki.host", id: "deltaURL", text: deltaField(\.address))
            tokenField(.delta, id: "deltaToken", text: deltaField(\.token))
            serverField("SHA-256 SPKI сервера (необязательно)", id: "deltaPin", text: deltaField(\.pin))
            Button("Обменяться изменениями") { Task { await syncImportedCards() } }
                .disabled(isServerBusy)
                .accessibilityIdentifier("deltaSync")
            if let deltaStatus {
                Text(deltaStatus).accessibilityIdentifier("deltaStatus")
            }
        } header: {
            Text("Импортированные карточки")
        } footer: {
            Text("Данные для подключения не используются для снимков. Обмен не меняет ручные карточки.")
        }
    }

    func serverField(_ title: LocalizedStringKey, id: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .autocorrectionDisabled()
            .noAutocapitalization()
            .disabled(isServerBusy)
            .accessibilityIdentifier(id)
    }

    func tokenField(_ scope: ServerTokenStore.Scope, id: String, text: Binding<String>) -> some View {
        SecureField("Токен", text: text)
            .autocorrectionDisabled()
            .noAutocapitalization()
            .disabled(isServerBusy)
            .accessibilityIdentifier(id)
            .focused($focusedToken, equals: scope)
            .submitLabel(.done)
            .onSubmit { focusedToken = nil }
    }

    func snapshotField(_ field: WritableKeyPath<ServerCredentialDraft, String>) -> Binding<String> {
        draftField(field, in: $snapshot, status: $snapshotStatus)
    }

    func deltaField(_ field: WritableKeyPath<ServerCredentialDraft, String>) -> Binding<String> {
        draftField(field, in: $delta, status: $deltaStatus)
    }

    func draftField(
        _ field: WritableKeyPath<ServerCredentialDraft, String>,
        in draft: Binding<ServerCredentialDraft>,
        status: Binding<String?>
    ) -> Binding<String> {
        Binding(
            get: { draft.wrappedValue[keyPath: field] },
            set: { value in
                guard !isServerBusy, draft.wrappedValue.update(field, to: value) else { return }
                status.wrappedValue = nil
            }
        )
    }

    @MainActor
    func syncImportedCards() async {
        guard !isServerBusy else { return }
        isServerBusy = true
        focusedToken = nil
        defer { isServerBusy = false }
        deltaStatus = "Обмен изменениями…"
        do {
            let (configuration, credentials) = try delta.connection(for: .delta)
            let result = try await ImportedDeltaSync.run(configuration: configuration, token: credentials.token, pin: credentials.pin)
            deltaStatus = deltaSummary(result, credentials: credentials, configuration: configuration)
            NotificationCenter.default.post(name: .kankiImportedCardsChanged, object: nil)
        } catch {
            deltaStatus = message(for: error)
        }
    }

    func deltaSummary(
        _ result: ImportedDeltaSync.Result,
        credentials: ServerTokenStore.Credentials,
        configuration: ServerConfiguration
    ) -> String {
        var status = "Прочитано: \(result.pulled). Доставлено: \(result.pushed). "
            + "Расхождения Anki: \(result.progressConflicts), публикаций: \(result.publicationConflicts)."
        if result.quarantined > 0 { status += " В карантине: \(result.quarantined)." }
        if let error = result.pullError { status += " Не удалось получить: \(message(for: error))." }
        if let error = result.pushError { status += " Не удалось отправить: \(message(for: error))." }
        do {
            try ServerTokenStore.save(credentials, for: .delta, configuration: configuration)
            deltaAddress = configuration.displayValue
        } catch {
            status += " Не удалось сохранить настройки: \(message(for: error))."
        }
        return status
    }

    var dataSection: some View {
        Section("Данные") {
            Text(
                "Карточки и история оценок хранятся на этом устройстве; JSON-экспорт — в меню «Экспорт» раздела «Обучение». "
                    + "Копию можно вручную отправить на сервер."
            )
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    var aboutSection: some View {
        Section("О приложении") {
            LabeledContent("Версия", value: appVersion)
            LabeledContent("Сборка", value: buildNumber)
        }
    }

    func loadDrafts() {
        guard !didLoadDrafts else { return }
        didLoadDrafts = true
        // Старый адрес — только подсказка. Старый токен не был привязан к нему.
        snapshot.address = snapshotAddress.isEmpty ? UserDefaults.standard.string(forKey: "serverURL") ?? "" : snapshotAddress
        delta.address = deltaAddress
        do {
            if let configuration = ServerConfiguration(rawValue: snapshotAddress) {
                snapshot.token = try ServerTokenStore.load(for: .snapshot, configuration: configuration)?.token ?? ""
            }
        } catch {
            snapshotStatus = message(for: error)
        }
        do {
            if let configuration = ServerConfiguration(rawValue: deltaAddress),
               let credentials = try ServerTokenStore.load(for: .delta, configuration: configuration) {
                delta.token = credentials.token
                delta.pin = credentials.pin
            }
        } catch {
            deltaStatus = message(for: error)
        }
    }

    func activateSnapshot() throws -> ServerClient {
        let (configuration, credentials) = try snapshot.connection(for: .snapshot)
        try ServerTokenStore.save(credentials, for: .snapshot, configuration: configuration)
        let previous = ServerConfiguration(rawValue: snapshotAddress)
        if previous.map({ ServerTokenStore.sameOrigin($0, configuration) }) != true {
            serverRevision = 0
            syncProblem = nil
            NotificationCenter.default.post(name: .kankiCancelPendingPush, object: nil)
        }
        pushGate.markChanged()
        snapshotAddress = configuration.displayValue
        return ServerClient(configuration: configuration, token: credentials.token, session: DeltaTransport.snapshotSession)
    }

    @MainActor
    func checkServer() async {
        guard !isServerBusy else { return }
        guard !pushGate.isRunning, !pushGate.isManualSyncRunning else {
            snapshotStatus = "Дождитесь завершения синхронизации и повторите."
            return
        }
        isServerBusy = true
        focusedToken = nil
        defer { isServerBusy = false }
        do {
            let identity = try await activateSnapshot().identity()
            snapshotStatus = "Подключено: \(identity.label)"
        } catch {
            snapshotStatus = message(for: error)
        }
    }

    func beginManualSnapshotSync() -> Bool {
        guard !isServerBusy else { return false }
        guard pushGate.beginManualSync() else {
            snapshotStatus = "Дождитесь завершения синхронизации и повторите."
            return false
        }
        isServerBusy = true
        focusedToken = nil
        NotificationCenter.default.post(name: .kankiCancelPendingPush, object: nil)
        return true
    }

    func finishManualSnapshotSync() {
        pushGate.finishManualSync()
        isServerBusy = false
    }

    @MainActor
    func pushSnapshot() async {
        guard beginManualSnapshotSync() else { return }
        defer { finishManualSnapshotSync() }
        do {
            let client = try activateSnapshot()
            let local = try LocalCardStore.load()
            let generation = pushGate.generation
            let result = try await client.push(snapshot: local, baseRevision: serverRevision)
            serverRevision = result.revision
            if pushGate.isCurrent(generation) {
                hasUnsyncedChanges = false
            }
            syncProblem = nil
            snapshotStatus = "Отправлено, ревизия \(result.revision)"
        } catch {
            if case .conflict(let revision) = error as? ServerError {
                syncProblem = .conflict(currentRevision: revision)
            }
            snapshotStatus = message(for: error)
        }
    }

    @MainActor
    func pullSnapshot() async {
        guard beginManualSnapshotSync() else { return }
        defer { finishManualSnapshotSync() }
        do {
            let client = try activateSnapshot()
            let generation = pushGate.generation
            let revision = serverRevision
            let result = try await client.fetchSnapshot()
            guard pushGate.isCurrent(generation), serverRevision == revision else {
                snapshotStatus = "Локальные данные изменились во время загрузки. Повторите загрузку."
                return
            }
            guard let snapshot = result.data else {
                snapshotStatus = "На сервере пока нет снимка"
                return
            }
            try LocalCardStore.replaceFromConfirmedPull(snapshot)
            serverRevision = result.revision
            hasUnsyncedChanges = false
            NotificationCenter.default.post(name: .kankiSnapshotReloaded, object: nil)
            syncProblem = nil
            snapshotStatus = "Загружено, ревизия \(result.revision)"
        } catch {
            snapshotStatus = message(for: error)
        }
    }

    func message(for error: Error) -> String {
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
        return error.localizedDescription
    }
}
