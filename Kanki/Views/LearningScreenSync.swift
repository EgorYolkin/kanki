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
    func schedulePush() {
        hasUnsyncedChanges = true
        guard let client = serverClient() else { return }
        pushTask?.cancel()
        pushTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await pushNow(client: client)
        }
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
        } catch let error as ServerError {
            if case .conflict(let current) = error {
                syncError = "Конфликт ревизий: на сервере \(current). Разрешите в настройках."
            }
        } catch {
            // Сеть недоступна; правки останутся помеченными до следующей попытки.
        }
    }

    /// Сверяет локальное состояние с сервером и приводит их к согласованности
    /// без тихого мержа: решение принимает `SnapshotSyncPlan`.
    func reconcile() async {
        guard let client = serverClient() else { return }
        pushTask?.cancel()
        do {
            let remote = try await client.fetchSnapshot()
            pushTask?.cancel()
            switch SnapshotSyncPlan.action(
                localDirty: hasUnsyncedChanges,
                knownRevision: serverRevision,
                remoteRevision: remote.revision,
                remoteDataEqualsLocal: remote.data == snapshot
            ) {
            case .noop:
                break
            case .pushLocal:
                await pushNow(client: client)
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
        } catch {
            // Сервер недоступен: тихо, повтор при следующей активации.
        }
    }
}
