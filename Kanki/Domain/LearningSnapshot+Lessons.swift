import Foundation

extension LearningSnapshot {
    var latestLesson: Lesson? { lessons.min(by: Lesson.newestFirst) }

    var courseNames: [String] { Set(lessons.lazy.compactMap(\.course)).sorted() }

    func lessons(inCourse course: String?) -> [Lesson] {
        lessons.filter { $0.course == course }.sorted(by: Lesson.newestFirst)
    }

    func matchingLessons(_ query: String) -> [Lesson] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return lessons
            .filter {
                term.isEmpty || $0.title.localizedCaseInsensitiveContains(term) || $0.course?.localizedCaseInsensitiveContains(term) == true
            }
            .sorted(by: Lesson.newestFirst)
    }

    func lesson(titled title: String, course: String?) -> Lesson? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let course = Lesson.normalizedCourse(course)
        return lessons.first { $0.title == title && $0.course == course }
    }

    /// В деталях видны все члены урока; сеанс исключает только архивные, а не будущие.
    func cards(forLessonID id: UUID) -> [SessionCard] {
        lessonCards(id: id, includingArchived: true)
    }

    func reviewCards(forLessonID id: UUID) -> [SessionCard] {
        lessonCards(id: id, includingArchived: false)
    }

    private func lessonCards(id: UUID, includingArchived: Bool) -> [SessionCard] {
        guard let lesson = lessons.first(where: { $0.id == id }), !lesson.cardIDs.isEmpty else { return [] }
        let indices = Dictionary(uniqueKeysWithValues: cards.indices.lazy.map { (cards[$0].id, $0) })
        return lesson.cardIDs.compactMap { cardID in
            guard let index = indices[cardID], includingArchived || !cards[index].isArchived else { return nil }
            return cards[index]
        }
    }

    mutating func createLesson(id: UUID, title: String, course: String?, sourceURL: URL?, createdAt: Date) throws {
        guard !lessons.contains(where: { $0.id == id }) else { throw LessonError.duplicateID }
        let lesson = Lesson(
            id: id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            course: Lesson.normalizedCourse(course),
            sourceURL: sourceURL,
            createdAt: createdAt,
            cardIDs: []
        )
        try validateLessonEdit(lesson)
        lessons.append(lesson)
        snapshotVersion = max(snapshotVersion, Self.lessonSnapshotVersion)
    }

    mutating func updateLesson(id: UUID, title: String, course: String?, sourceURL: URL?) throws {
        let index = try lessonIndex(id)
        var edited = lessons[index]
        edited.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        edited.course = Lesson.normalizedCourse(course)
        edited.sourceURL = sourceURL
        try validateLessonEdit(edited)
        lessons[index] = edited
    }

    mutating func removeLesson(id: UUID) throws {
        let index = try lessonIndex(id)
        lessons.remove(at: index)
    }

    mutating func addCard(_ card: SessionCard, toLessonID id: UUID) throws {
        let index = try lessonIndex(id)
        guard !cards.contains(where: { $0.id == card.id }) else { throw LessonError.duplicateCard }
        cards.append(card)
        lessons[index].cardIDs.append(card.id)
    }

    private func lessonIndex(_ id: UUID) throws -> Int {
        guard let index = lessons.firstIndex(where: { $0.id == id }) else { throw LessonError.missingLesson }
        return index
    }

    private func validateLessonEdit(_ edited: Lesson) throws {
        try edited.validateFields()
        if lessons.contains(where: { $0.id != edited.id && $0.course == edited.course && $0.title == edited.title }) {
            throw LessonError.duplicateName
        }
    }

    func validateLessons(cardIDs: Set<UUID>) throws {
        var ids = Set<UUID>(minimumCapacity: lessons.count)
        var names = Set<LessonIdentity>(minimumCapacity: lessons.count)
        for lesson in lessons {
            try lesson.validateFields()
            guard ids.insert(lesson.id).inserted else { throw LessonError.duplicateID }
            guard names.insert(LessonIdentity(course: lesson.course, title: lesson.title)).inserted else { throw LessonError.duplicateName }
            var members = Set<UUID>(minimumCapacity: lesson.cardIDs.count)
            for member in lesson.cardIDs {
                guard cardIDs.contains(member), members.insert(member).inserted else { throw LessonError.invalidMembership }
            }
        }
    }
}

private struct LessonIdentity: Hashable {
    let course: String?
    let title: String
}
