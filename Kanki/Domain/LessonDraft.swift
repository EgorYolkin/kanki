import Foundation

struct LessonDraft {
    var title: String
    var course: String?
    var source: String
    var originalMetadata: Lesson.Metadata? = nil

    func hasMetadataConflict(in snapshot: LearningSnapshot) -> Bool {
        guard let originalMetadata else { return false }
        return snapshot.lessons.first { $0.id == originalMetadata.id }?.metadata != originalMetadata
    }

    var normalizedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    var normalizedCourse: String? { Lesson.normalizedCourse(course) }

    private var trimmedSource: String { source.trimmingCharacters(in: .whitespacesAndNewlines) }

    var sourceURL: URL? {
        let text = trimmedSource
        guard !text.isEmpty, !text.contains(where: \.isWhitespace),
              let url = URL(string: text), Lesson.isValidSourceURL(url) else { return nil }
        return url
    }

    var validationError: String? {
        if normalizedTitle.isEmpty { return LessonError.invalidTitle.rawValue }
        if normalizedCourse == Lesson.noCourseTitle { return LessonError.invalidCourse.rawValue }
        if !trimmedSource.isEmpty, sourceURL == nil { return LessonError.invalidSourceURL.rawValue }
        return nil
    }
}
