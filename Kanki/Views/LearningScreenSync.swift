import Foundation
import SwiftUI

/// Синхронизационный движок экрана «Обучение»: вынесен из `LearningScreen.swift`
/// ради лимита длины файла. Члены internal: расширение в другом файле не видит
/// `private`-члены структуры.
extension LearningScreen {
    var isOperationAlertPresented: Binding<Bool> {
        Binding(
            get: { operationAlert != nil },
            set: { if !$0 { operationAlert = nil } }
        )
    }

    func serverClient() -> ServerClient? {
        guard let (configuration, token) = serverCredentials() else { return nil }
        return ServerClient(configuration: configuration, token: token)
    }

    private func serverCredentials() -> (ServerConfiguration, String)? {
        guard let configuration = ServerConfiguration(rawValue: serverURL) else { return nil }
        do {
            guard let stored = try ServerTokenStore.load() else { return nil }
            let token = stored.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { return nil }
            return (configuration, token)
        } catch {
            return nil
        }
    }

    /// Отмечает состояние несинхронизированным и ставит отложенный push после правки.
    /// Дебаунс-задача не выполняет сам PUT: отмена таймера не должна
    /// абортировать уже отправленный запрос.
    func schedulePush() {
        hasUnsyncedChanges = true
        pushGate.markChanged()
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
            isConfigured: serverCredentials() != nil,
            problem: syncProblem,
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

    /// Успех фиксирует ревизию; чистота подтверждается только для отправленного поколения.
    func pushNow(client: ServerClient) async {
        pushDebounceTask?.cancel()
        pushDebounceTask = nil
        let localSnapshot = snapshot
        let baseRevision = serverRevision
        let generation = pushGate.generation
        do {
            let result = try await client.push(
                snapshot: localSnapshot,
                baseRevision: baseRevision
            )
            serverRevision = result.revision
            if pushGate.isCurrent(generation) {
                hasUnsyncedChanges = false
            }
            syncProblem = nil
        } catch {
            guard let problem = SyncStatus.Problem(error: error) else { return }
            recordSyncProblem(problem)
            if problem == .unauthorized {
                operationAlert = problem.text
            }
        }
    }

    private func recordSyncProblem(_ problem: SyncStatus.Problem) {
        syncProblem = SyncStatus.retainingConflict(syncProblem, onFailure: problem)
        if case .conflict(let revision) = problem {
            operationAlert = "Конфликт ревизий: на сервере \(revision). Разрешите в настройках."
        }
    }

    /// Сверяет локальное состояние с сервером и приводит их к согласованности
    /// без тихого мержа: решение принимает `SnapshotSyncPlan`.
    func reconcile() async {
        guard let client = serverClient() else { return }
        guard !isReconciling, !pushGate.isRunning, !pushGate.isManualSyncRunning else { return }
        isReconciling = true
        defer { isReconciling = false }
        // Отменяем только ещё не начатый отложенный push; идущий PUT не трогаем.
        pushDebounceTask?.cancel()
        pushDebounceTask = nil
        let generation = pushGate.generation
        let revision = serverRevision
        do {
            let remote = try await client.fetchSnapshot()
            guard pushGate.canApplyFetch(startedAt: generation), serverRevision == revision else { return }
            await apply(remote, client: client)
        } catch {
            guard pushGate.canApplyFetch(startedAt: generation), serverRevision == revision,
                  let problem = SyncStatus.Problem(error: error) else { return }
            recordSyncProblem(problem)
        }
    }

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
            return
        case .adoptRevision:
            serverRevision = remote.revision
            hasUnsyncedChanges = false
        case .applyRemote:
            guard let remoteSnapshot = remote.data else { return }
            do {
                try LocalCardStore.save(remoteSnapshot)
            } catch {
                recordSyncProblem(.localSaveFailed)
                return
            }
            serverRevision = remote.revision
            hasUnsyncedChanges = false
            reload()
        case .conflict:
            recordSyncProblem(.conflict(currentRevision: remote.revision))
            return
        }
        syncProblem = nil
    }
}

extension Notification.Name {
    /// Ручные push/pull из настроек: отменить ещё не начатый авто-push,
    /// чтобы он не ушёл параллельно и не дал ложный 409.
    static let kankiCancelPendingPush = Notification.Name("kanki.cancelPendingPush")
}
