import Foundation
import SwiftUI

struct StatisticsScreen: View {
    private enum Phase {
        case loading
        case unconfigured
        case loaded(StatisticsOverview)
        case failed(String)
    }

    @AppStorage("serverURL") private var serverURL = ""
    @Environment(\.scenePhase) private var scenePhase
    @State private var phase = Phase.loading
    @State private var refreshID = 0
    @State private var calendarSelection = StatisticsHeatmap.Selection()

    var body: some View {
        ZStack {
            switch phase {
            case .loading:
                ProgressView("Загружаем статистику…")
            case .unconfigured:
                SectionIntro(
                    symbol: "server.rack",
                    title: "Сервер не настроен",
                    detail: "Укажите адрес и токен во вкладке «Настройки», чтобы увидеть общую статистику устройств."
                )
            case .loaded(let overview):
                if overview.isEmpty {
                    SectionIntro(
                        symbol: "chart.bar",
                        title: "Активности пока нет",
                        detail: "Здесь появятся посещения и повторения, когда они поступят на сервер."
                    )
                } else {
                    StatisticsDashboard(overview: overview, calendarSelection: $calendarSelection)
                }
            case .failed(let message):
                SectionIntro(symbol: "exclamationmark.triangle", title: "Не удалось загрузить статистику", detail: message)
            }
        }
        .navigationTitle("Статистика")
        .toolbar {
            Button {
                refreshID += 1
            } label: {
                Label("Обновить статистику", systemImage: "arrow.clockwise")
            }
            .accessibilityIdentifier("refreshStatistics")
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refreshID += 1 }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in refreshID += 1 }
        .task(id: scenePhase == .active ? refreshID : nil) {
            guard scenePhase == .active else { return }
            await load()
        }
        .onDisappear { phase = .loading }
    }

    private func load() async {
        if case .failed = phase { phase = .loading }
        do {
            guard let configuration = ServerConfiguration(rawValue: serverURL),
                  let token = try ServerTokenStore.load(), !token.isEmpty else {
                phase = .unconfigured
                return
            }

            let client = ServerClient(configuration: configuration, token: token)
            let statistics = try await client.statistics(timeZone: .current)
            try Task.checkCancellation()
            phase = .loaded(try StatisticsOverview(statistics))
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(message(for: error))
        }
    }

    private func message(for error: Error) -> String {
        switch error as? ServerError {
        case .unauthorized: "Токен отклонён. Проверьте его в настройках сервера."
        case .http(let status): "Ошибка сервера: \(status)."
        case .decoding, .invalidResponse, .conflict: "Сервер вернул неожиданные данные."
        case nil: error.localizedDescription
        }
    }
}
