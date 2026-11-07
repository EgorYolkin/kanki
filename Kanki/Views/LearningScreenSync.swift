import Foundation
import SwiftUI

/// Синхронизационный движок экрана «Обучение»: вынесен из `LearningScreen.swift`
/// ради лимита длины файла. Члены internal: расширение в другом файле не видит
/// `private`-члены структуры.
extension LearningScreen {
    var isSyncErrorPresented: Binding<Bool> {
        Binding(
            get: { syncError != nil },
            set: { if !$0 { syncError = nil } }
        )
    }

    func serverClient() -> ServerClient? {
        guard let rawURL = UserDefaults.standard.string(forKey: "serverURL"),
              let configuration = ServerConfiguration(rawValue: rawURL)
        else {
            return nil
        }
        do {
            guard let stored = try ServerTokenStore.load() else { return nil }
            let token = stored.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { return nil }
            return ServerClient(configuration: configuration, token: token)
        } catch {
            return nil
        }
    }

    /// Отмечает состояние несинхронизированным и ставит отложенный push после правки.
    /// Дебаунс-задача не выполняет сам PUT: отмена таймера не должна
    /// абортировать уже отправленный запрос.
    func schedulePush() {
        hasUnsyncedChanges = true
        guard let client = serverClient() else { return }
        pushDebounceTask?.cancel()
        pushDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            pushDebounceTask = nil
            Task { @MainActor in await requestPush(client: client) }
        }
    }

    @ViewBuilder
    var emptyCardsSection: some View {
        Section {
            SectionIntro(
                symbol: "rectangle.stack",
                title: "Карточек пока нет",
                detail: "Добавьте карточку с вопросом и ответом кнопкой «плюс»."
            )
            .frame(maxWidth: .infinity)
        }
    }

    /// Честный текст статуса синхронизации; `nil` — сервер не настроен, строки нет.
    var syncStatusText: String? {
        SyncStatus.text(
            isConfigured: serverClient() != nil,
            hasConflict: syncError != nil,
            lastSyncFailed: lastSyncFailed,
            hasUnsyncedChanges: hasUnsyncedChanges,
            knownRevision: serverRevision
        )
    }

    /// Один пуш в полёте: правка во время отправки ждёт завершения
    /// и повторяется, а не отменяет PUT (отмена дала бы ложный 409).
    func requestPush(client: ServerClient) async {
        guard pushGate.begin() else { return }
        repeat {
            await pushNow(client: client)
        } while pushGate.finishAndNeedsAnother()
    }

    /// Отправляет текущий снимок на сервер; успех фиксирует ревизию и чистоту локала.
    func pushNow(client: ServerClient) async {
        let localSnapshot = snapshot
        let baseRevision = serverRevision
        do {
            let result = try await client.push(
                snapshot: localSnapshot,
                baseRevision: baseRevision
            )
            serverRevision = result.revision
            hasUnsyncedChanges = false
            lastSyncFailed = false
        } catch let error as ServerError {
            switch error {
            case .conflict(let current):
                syncError = "Конфликт ревизий: на сервере \(current). Разрешите в настройках."
            case .unauthorized:
                syncError = "Токен отклонён — проверьте настройки сервера"
            case .invalidResponse, .http, .decoding:
                lastSyncFailed = true
            }
        } catch is CancellationError {
            // Отмена задачи синка не означает, что сервер недоступен.
        } catch let error as URLError where error.code == .cancelled {
            // То же для отменённого URLSession-запроса.
        } catch {
            lastSyncFailed = true
            // Сеть недоступна; правки останутся помеченными до следующей попытки.
        }
    }

    /// Сверяет локальное состояние с сервером и приводит их к согласованности
    /// без тихого мержа: решение принимает `SnapshotSyncPlan`.
    func reconcile() async {
        guard let client = serverClient() else { return }
        guard !isReconciling else { return }
        isReconciling = true
        defer { isReconciling = false }
        // Отменяем только ещё не начатый отложенный push; идущий PUT не трогаем.
        pushDebounceTask?.cancel()
        do {
            let remote = try await client.fetchSnapshot()
            lastSyncFailed = false
            await apply(remote, client: client)
        } catch is CancellationError {
            // Уход экрана не означает, что сервер недоступен.
        } catch let error as URLError where error.code == .cancelled {
            // То же для отменённого URLSession-запроса.
        } catch {
            lastSyncFailed = true
            // Сервер недоступен: тихо, повтор при следующей активации.
        }
    }

    /// Применяет решение `SnapshotSyncPlan` к уже полученному серверному снимку.
    private func apply(_ remote: ServerSnapshot, client: ServerClient) async {
        switch SnapshotSyncPlan.action(
            localDirty: hasUnsyncedChanges,
            knownRevision: serverRevision,
            remoteRevision: remote.revision,
            // Сравнение на точности провода: иначе дробные секунды дают
            // ложный конфликт для уже применённого PUT.
            remoteDataEqualsLocal: remote.data == ServerClient.wireNormalized(snapshot)
        ) {
        case .noop:
            break
        case .pushLocal:
            await requestPush(client: client)
        case .adoptRevision:
            serverRevision = remote.revision
            hasUnsyncedChanges = false
        case .applyRemote:
            guard let remoteSnapshot = remote.data else { return }
            do {
                try LocalCardStore.save(remoteSnapshot)
            } catch {
                loadError = "Не удалось сохранить загруженный снимок: \(error.localizedDescription)"
                return
            }
            serverRevision = remote.revision
            hasUnsyncedChanges = false
            reload()
        case .conflict:
            syncError = "Конфликт ревизий: на сервере \(remote.revision). Разрешите в настройках."
        }
    }
}

extension Notification.Name {
    /// Ручные push/pull из настроек: отменить ещё не начатый авто-push,
    /// чтобы он не ушёл параллельно и не дал ложный 409.
    static let kankiCancelPendingPush = Notification.Name("kanki.cancelPendingPush")
}
