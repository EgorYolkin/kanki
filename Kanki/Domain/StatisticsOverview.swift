import Foundation

/// Данные для диаграмм и календаря. Даты сервера уже относятся к часовому поясу запроса.
struct StatisticsOverview {
    struct Week {
        let days: ArraySlice<StudyStatistics.Day>
        let leadingBlanks: Int
        let monthLabel: String?
    }

    let statistics: StudyStatistics
    let weeks: [Week]
    let isEmpty: Bool
    let largestTopicCount: Int

    init(_ statistics: StudyStatistics) throws {
        guard statistics.ratings.count == RecallRating.allCases.count else {
            throw ServerError.decoding
        }

        self.statistics = statistics
        isEmpty = statistics.totalReviews == 0 && !statistics.days.contains { $0.visits > 0 }
        largestTopicCount = statistics.topics.lazy.map(\.count).max() ?? 0
        weeks = try Self.weeks(for: statistics.days)
    }

    private static func weeks(for days: [StudyStatistics.Day]) throws -> [Week] {
        guard let first = days.first else { return [] }

        // Не преобразуем локальную дату отчёта во время устройства: для раскладки
        // нужен лишь день недели григорианского календаря.
        let dateStyle = Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        calendar.locale = Locale(identifier: "ru_RU")
        guard let firstDate = try? dateStyle.parse(first.date) else { throw ServerError.decoding }

        let monthNames = calendar.shortMonthSymbols
        let weekday = calendar.component(.weekday, from: firstDate)
        var blanks = (weekday + 5) % 7 // Понедельник — первая строка, воскресенье — седьмая.
        var start = days.startIndex
        var weeks: [Week] = []
        weeks.reserveCapacity((days.count + blanks + 6) / 7)
        while start < days.endIndex {
            let end = min(start + 7 - blanks, days.endIndex)
            let day = days[start].date
            var monthLabel: String?
            if blanks == 0 && day.suffix(2) <= "07" {
                guard let month = Int(day.dropFirst(5).prefix(2)), (1...12).contains(month) else {
                    throw ServerError.decoding
                }
                monthLabel = monthNames[month - 1]
            }
            weeks.append(Week(days: days[start..<end], leadingBlanks: blanks, monthLabel: monthLabel))
            blanks = 0
            start = end
        }
        return weeks
    }

    /// Фиксированная шкала позволяет сравнивать ячейки разных недель и устройств.
    static func intensity(for count: Int) -> Double {
        switch count {
        case ...0: 0
        case 1: 0.3
        case 2...4: 0.5
        case 5...9: 0.75
        default: 1
        }
    }
}
