import Foundation

/// Источник карточек, не отдельная колода или расписание.
struct Lesson: Identifiable, Equatable, Codable {
    static let noCourseTitle = "Без курса"

    let id: UUID
    var title: String
    var course: String?
    var sourceURL: URL?
    let createdAt: Date
    var cardIDs: [UUID]

    /// Baseline редактора: членство и история не конфликтуют с правкой метаданных.
    struct Metadata: Equatable {
        let id: UUID
        let title: String
        let course: String?
        let sourceURL: URL?
    }

    var metadata: Metadata { Metadata(id: id, title: title, course: course, sourceURL: sourceURL) }

    enum CodingKeys: String, CodingKey {
        case id, title, course, createdAt
        case sourceURL = "source_url"
        case cardIDs = "card_ids"
    }

    static func normalizedCourse(_ course: String?) -> String? {
        guard let course = course?.trimmingCharacters(in: .whitespacesAndNewlines), !course.isEmpty else { return nil }
        return course
    }

    static func isValidSourceURL(_ url: URL) -> Bool {
        guard url.baseURL == nil, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host(percentEncoded: false), !host.isEmpty else { return false }
        return host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
    }

    /// Операции ввода нормализуют имена до записи; при чтении не исправляем повреждённый снимок.
    func validateFields() throws {
        guard !title.isEmpty, title == title.trimmingCharacters(in: .whitespacesAndNewlines) else { throw LessonError.invalidTitle }
        guard course == Self.normalizedCourse(course), course != Self.noCourseTitle else { throw LessonError.invalidCourse }
        if let sourceURL, !Self.isValidSourceURL(sourceURL) { throw LessonError.invalidSourceURL }
    }

    /// При одинаковой дате меньший UUID идёт первым независимо от порядка загрузки.
    static func newestFirst(_ left: Self, _ right: Self) -> Bool {
        if left.createdAt == right.createdAt { return left.id.uuidString < right.id.uuidString }
        return left.createdAt > right.createdAt
    }
}

enum LessonError: String, LocalizedError {
    case invalidTitle = "Введите название урока без пробелов по краям."
    case invalidCourse = "Введите название курса или выберите «Без курса»."
    case invalidSourceURL = "Введите полную ссылку на видео (http или https)."
    case duplicateName = "Урок с таким названием уже есть в этом курсе."
    case duplicateID = "Идентификатор урока уже используется."
    case staleMetadata = "Урок изменён на другом устройстве. Ваш черновик сохранён в форме. Скопируйте черновик и откройте урок заново для сверки."
    case missingLesson = "Урок больше недоступен."
    case duplicateCard = "Идентификатор карточки уже используется."
    case invalidMembership = "Урок содержит отсутствующую или повторяющуюся карточку."

    var errorDescription: String? { rawValue }
}
