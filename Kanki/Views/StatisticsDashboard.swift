import Charts
import SwiftUI

struct StatisticsDashboard: View {
    let overview: StatisticsOverview
    @Binding var calendarSelection: StatisticsHeatmap.Selection

    private var statistics: StudyStatistics { overview.statistics }

    var body: some View {
        List {
            Section("Итоги за всё время") {
                metric("Всего повторений", count: statistics.totalReviews, identifier: "statisticsTotalReviews")
                metric("Дней подряд", count: statistics.streakDays, identifier: "statisticsStreak")
                Text("Серия продолжается, если последнее повторение было сегодня или вчера.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Последние 7 дней") {
                dailyChart
            }
            Section("Календарь за год") {
                StatisticsHeatmap(overview: overview, selection: $calendarSelection)
            }
            if statistics.totalReviews > 0 {
                Section("Оценки за всё время") {
                    ratingChart
                }
                Section("Повторения по темам") {
                    topicRows
                }
            } else {
                Section("Повторения") {
                    Text("Повторений пока нет. После первого ответа здесь появятся оценки и темы.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func metric(_ title: String, count: Int, identifier: String) -> some View {
        LabeledContent(title, value: count.formatted())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(String(count))
            .accessibilityIdentifier(identifier)
    }

    private var dailyChart: some View {
        Chart(statistics.days.suffix(7), id: \.date) { day in
            let label = String(day.date.suffix(2))
            dailyBar(label: label, date: day.date, series: "Посещения", count: day.visits)
            dailyBar(label: label, date: day.date, series: "Повторения", count: day.reviews)
        }
        .chartYAxis { AxisMarks(values: .automatic(minimumStride: 1)) }
        .frame(height: 170)
        .padding(.vertical, 8)
        .accessibilityLabel("Посещения и повторения по дням")
    }

    private func dailyBar(label: String, date: String, series: String, count: Int) -> some ChartContent {
        BarMark(x: .value("День месяца", label), y: .value("Количество", count))
            .foregroundStyle(by: .value("Активность", series))
            .position(by: .value("Активность", series))
            .accessibilityLabel("\(date), \(series)")
            .accessibilityValue("\(count)")
    }

    private var ratingChart: some View {
        Chart(RecallRating.allCases, id: \.rawValue) { rating in
            let count = statistics.ratings[rating.rawValue - 1]
            BarMark(x: .value("Оценка", rating.title), y: .value("Ответы", count))
                .foregroundStyle(rating.tint)
                .annotation(position: .top) { Text(count, format: .number).font(.caption) }
                .accessibilityLabel(rating.title)
                .accessibilityValue("Ответов: \(count)")
        }
        .chartYAxis { AxisMarks(values: .automatic(minimumStride: 1)) }
        .frame(height: 170)
        .padding(.vertical, 8)
        .accessibilityLabel("Распределение оценок")
    }

    @ViewBuilder
    private var topicRows: some View {
        if overview.largestTopicCount > 0 {
            ForEach(statistics.topics, id: \.name) { topic in
                VStack(alignment: .leading, spacing: 5) {
                    LabeledContent(topic.name, value: topic.count, format: .number)
                    ProgressView(value: Double(topic.count), total: Double(overview.largestTopicCount))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(topic.name)
                .accessibilityValue("Повторений: \(topic.count)")
                .accessibilityIdentifier("statisticsTopic-\(topic.name)")
            }
        } else {
            Text("Нет данных о темах.").foregroundStyle(.secondary)
        }
    }
}
