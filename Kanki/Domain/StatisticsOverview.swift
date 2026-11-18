import Foundation

/// Данные для диаграмм и календаря. Даты сервера уже относятся к часовому поясу запроса.
struct StatisticsOverview {
    struct Week {
        let days: ArraySlice<StudyStatistics.Day>
        let leadingBlanks: Int
        let monthLabel: String?
    }

    // Даты отчёта — календарные дни, а не моменты времени на устройстве.
    static let dayFormat = Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day()

    let statistics: StudyStatistics
    let weeks: [Week]
    let dateRange: ClosedRange<Date>?
    let isEmpty: Bool
    let largestTopicCount: Int

    init(_ statistics: StudyStatistics) throws {
        guard statistics.ratings.count == RecallRating.allCases.count else {
            throw ServerError.decoding
        }

        self.statistics = statistics
        isEmpty = statistics.totalReviews == 0 && !statistics.days.contains { $0.visits > 0 }
        largestTopicCount = statistics.topics.lazy.map(\.count).max() ?? 0
        if let first = statistics.days.first, let last = statistics.days.last {
            guard let start = try? Self.dayFormat.parse(first.date),
                  let end = try? Self.dayFormat.parse(last.date), start <= end else { throw ServerError.decoding }

            dateRange = start...end
            weeks = try Self.weeks(for: statistics.days, starting: start)
        } else {
            dateRange = nil
            weeks = []
        }
    }

    /// Если выбранная дата вышла из окна отчёта, показываем самый свежий день.
    func day(for selectedDate: String?) -> StudyStatistics.Day? {
        if let selectedDate, let day = statistics.days.first(where: { $0.date == selectedDate }) {
            return day
        }

        return statistics.days.last
    }

    private static func weeks(for days: [StudyStatistics.Day], starting firstDate: Date) throws -> [Week] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        calendar.locale = Locale(identifier: "ru_RU")

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
