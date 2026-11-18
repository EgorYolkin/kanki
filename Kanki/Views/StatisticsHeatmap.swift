import SwiftUI

struct StatisticsHeatmap: View {
    struct Selection {
        var showsVisits: Bool?
        var date: String?
    }

    let overview: StatisticsOverview
    @Binding var selection: Selection

    @ScaledMetric(relativeTo: .caption) private var cellSide: CGFloat = 16

    private var showsVisits: Bool { selection.showsVisits ?? (overview.statistics.totalReviews == 0) }

    var body: some View {
        let detailDay = overview.day(for: selection.date)
        VStack(alignment: .leading, spacing: 12) {
            Picker("Показатель календаря", selection: Binding(get: { showsVisits }, set: { selection.showsVisits = $0 })) {
                Text("Повторения").tag(false)
                Text("Посещения").tag(true)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("statisticsCalendarMetric")
            if let day = detailDay {
                datePicker(for: day)
            }

            HStack(alignment: .top, spacing: 4) {
                weekdayLabels
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 3) {
                        ForEach(overview.weeks, id: \.days.startIndex) { week in
                            weekColumn(week, selectedDate: detailDay?.date)
                        }
                    }
                    .padding(.bottom, 5)
                }
                .defaultScrollAnchor(.trailing)
            }
            legend
            if let day = detailDay {
                Text("\(day.date) · Посещений: \(day.visits) · Повторений: \(day.reviews)")
                    .font(.footnote)
                    .accessibilityIdentifier("statisticsCalendarDay")
            }
        }
        .padding(.vertical, 6)
        .onAppear {
            if selection.showsVisits == nil { selection.showsVisits = showsVisits }
        }
    }

    @ViewBuilder
    private func datePicker(for day: StudyStatistics.Day) -> some View {
        if let range = overview.dateRange, let date = try? StatisticsOverview.dayFormat.parse(day.date) {
            DatePicker(
                "Выбрать дату",
                selection: Binding(get: { date }, set: { selection.date = StatisticsOverview.dayFormat.format($0) }),
                in: range,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .environment(\.timeZone, .gmt)
            .accessibilityIdentifier("statisticsCalendarDate")
        }
    }

    private var weekdayLabels: some View {
        VStack(alignment: .leading, spacing: 3) {
            Color.clear.frame(width: 1, height: cellSide)
            ForEach(["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"], id: \.self) { weekday in
                Text(weekday).frame(height: cellSide)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    private func weekColumn(_ week: StatisticsOverview.Week, selectedDate: String?) -> some View {
        VStack(spacing: 3) {
            Color.clear
                .frame(width: cellSide, height: cellSide)
                .overlay(alignment: .leading) {
                    if let month = week.monthLabel {
                        Text(month).font(.caption2).fixedSize().accessibilityHidden(true)
                    }
                }
            ForEach(0..<week.leadingBlanks, id: \.self) { _ in
                Color.clear.frame(width: cellSide, height: cellSide).accessibilityHidden(true)
            }
            ForEach(week.days, id: \.date) { day in
                dayButton(day, isSelected: day.date == selectedDate)
            }
        }
    }

    private func dayButton(_ day: StudyStatistics.Day, isSelected: Bool) -> some View {
        Button {
            selection.date = day.date
        } label: {
            RoundedRectangle(cornerRadius: 3)
                .fill(color(for: showsVisits ? day.visits : day.reviews))
                .frame(width: cellSide, height: cellSide)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 3).strokeBorder(.primary, lineWidth: 1.5)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.date)
        .accessibilityValue("Посещений: \(day.visits), повторений: \(day.reviews)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var legend: some View {
        HStack(spacing: 5) {
            Text("Меньше")
            ForEach([0, 1, 2, 5, 10], id: \.self) { value in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color(for: value))
                    .frame(width: 10, height: 10)
            }
            Text("Больше")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    private func color(for count: Int) -> Color {
        count == 0 ? Color.secondary.opacity(0.18) : Color.green.opacity(StatisticsOverview.intensity(for: count))
    }
}
