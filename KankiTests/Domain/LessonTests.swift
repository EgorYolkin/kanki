import XCTest
@testable import Kanki

final class LessonTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 100)

    private func id(_ number: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, number))
    }

    private func card(_ number: UInt8) -> SessionCard {
        SessionCard(id: id(number), question: "Вопрос \(number)", answer: "Ответ", createdAt: now)
    }

    func testCatalogSortsAndSearchesWithoutMergingCourseIdentities() throws {
        var snapshot = LearningSnapshot()
        XCTAssertNil(snapshot.latestLesson)
        let recent = now.addingTimeInterval(5)
        try snapshot.createLesson(id: id(3), title: "Введение", course: " Swift ", sourceURL: nil, createdAt: recent)
        try snapshot.createLesson(id: id(1), title: "Введение", course: "Python", sourceURL: nil, createdAt: recent)
        try snapshot.createLesson(id: id(2), title: "Следующий", course: "Swift", sourceURL: nil, createdAt: now)
        try snapshot.createLesson(id: id(4), title: " Введение ", course: "\n", sourceURL: nil, createdAt: now)
        try snapshot.createLesson(id: id(5), title: "Введение", course: "swift", sourceURL: nil, createdAt: now)

        XCTAssertEqual(snapshot.courseNames, ["Python", "Swift", "swift"])
        XCTAssertEqual(snapshot.latestLesson?.id, id(1))
        XCTAssertEqual(snapshot.lesson(titled: " Введение", course: "Swift\n")?.id, id(3))
        XCTAssertEqual(snapshot.lesson(titled: "Введение", course: " ")?.id, id(4))
        XCTAssertNil(snapshot.lesson(titled: "введение", course: "Swift"))
        XCTAssertEqual(snapshot.lessons(inCourse: "Swift").map(\.id), [id(3), id(2)])
        XCTAssertEqual(snapshot.lessons(inCourse: nil).map(\.id), [id(4)])
        XCTAssertEqual(snapshot.matchingLessons(" виДео "), [])
        XCTAssertEqual(snapshot.matchingLessons(" swIft ").map(\.id), [id(3), id(2), id(5)])
        XCTAssertEqual(snapshot.matchingLessons("ВВЕ").map(\.id), [id(1), id(3), id(4), id(5)])
        XCTAssertEqual(snapshot.matchingLessons(" ").count, 5)
    }

    func testEditKeepsMembershipAndDeletionKeepsCardsAndProgress() throws {
        var snapshot = LearningSnapshot()
        try snapshot.createLesson(id: id(1), title: "Урок", course: nil, sourceURL: nil, createdAt: now)
        let first = card(2)
        let second = card(3)
        try snapshot.addCard(second, toLessonID: id(1))
        try snapshot.addCard(first, toLessonID: id(1))
        try CardScheduling.record(first, rating: .good, in: &snapshot, at: now)
        let before = snapshot
        let link = try XCTUnwrap(URL(string: "https://example.org/video"))
        try snapshot.updateLesson(id: id(1), title: " Новое название ", course: "  Swift ", sourceURL: link)
        let lesson = try XCTUnwrap(snapshot.latestLesson)
        XCTAssertEqual(lesson, Lesson(id: id(1), title: "Новое название", course: "Swift", sourceURL: link, createdAt: now, cardIDs: [second.id, first.id]))
        XCTAssertEqual(snapshot.cards(forLessonID: id(1)), [second, first])
        try snapshot.removeLesson(id: id(1))
        XCTAssertTrue(snapshot.lessons.isEmpty)
        XCTAssertEqual(snapshot.snapshotVersion, 4)
        XCTAssertEqual(snapshot.cards, before.cards)
        XCTAssertEqual(snapshot.schedules, before.schedules)
        XCTAssertEqual(snapshot.reviews, before.reviews)
    }

    func testRejectedEditsNeverPartiallyMutate() throws {
        var snapshot = LearningSnapshot()
        try snapshot.createLesson(id: id(1), title: "Первый", course: nil, sourceURL: nil, createdAt: now)
        try snapshot.createLesson(id: id(2), title: "Второй", course: nil, sourceURL: nil, createdAt: now)
        try snapshot.addCard(card(3), toLessonID: id(1))
        let original = snapshot
        XCTAssertThrowsError(try snapshot.createLesson(id: id(1), title: "Третий", course: nil, sourceURL: nil, createdAt: now))
        XCTAssertThrowsError(try snapshot.createLesson(id: id(4), title: " Первый ", course: "\t", sourceURL: nil, createdAt: now))
        XCTAssertThrowsError(try snapshot.updateLesson(id: id(1), title: " Второй ", course: nil, sourceURL: nil))
        XCTAssertThrowsError(try snapshot.updateLesson(id: id(1), title: "\n", course: "Swift", sourceURL: nil))
        XCTAssertThrowsError(try snapshot.updateLesson(id: id(1), title: "Третий", course: " Без курса ", sourceURL: nil))
        let relative = try XCTUnwrap(URL(string: "video"))
        XCTAssertThrowsError(try snapshot.updateLesson(id: id(1), title: "Третий", course: nil, sourceURL: relative))
        XCTAssertThrowsError(try snapshot.addCard(card(3), toLessonID: id(2)))
        XCTAssertThrowsError(try snapshot.addCard(card(4), toLessonID: id(8)))
        XCTAssertThrowsError(try snapshot.removeLesson(id: id(8)))
        XCTAssertEqual(snapshot, original)
    }

    func testSharedCardUsesOneScheduleAndAllActiveMembersStayInOrder() throws {
        let shared = card(1)
        let new = card(2)
        let outsider = card(3)
        let first = Lesson(id: id(4), title: "Первый", course: "Swift", sourceURL: nil, createdAt: now, cardIDs: [new.id, shared.id])
        let second = Lesson(id: id(5), title: "Второй", course: nil, sourceURL: nil, createdAt: now, cardIDs: [shared.id])
        var snapshot = LearningSnapshot(cards: [outsider, shared, new], lessons: [second, first])
        try snapshot.validate()
        try CardScheduling.record(shared, rating: .easy, in: &snapshot, at: now)
        let due = try XCTUnwrap(snapshot.schedules[shared.id]?.due)
        XCTAssertGreaterThan(due, now)
        XCTAssertEqual(snapshot.reviews.map(\.cardID), [shared.id])
        XCTAssertEqual(Set(snapshot.schedules.keys), [shared.id])
        XCTAssertEqual(snapshot.reviewCards(forLessonID: first.id), [new, shared])
        XCTAssertEqual(snapshot.reviewCards(forLessonID: second.id), [shared])
        XCTAssertEqual(snapshot.reviewCards(forLessonID: id(9)), [])
        XCTAssertTrue(snapshot.setArchived(true, cardID: shared.id))
        XCTAssertEqual(snapshot.cards(forLessonID: first.id).map(\.id), [new.id, shared.id])
        XCTAssertEqual(snapshot.reviewCards(forLessonID: first.id), [new])
        XCTAssertEqual(snapshot.reviewCards(forLessonID: second.id), [])
        XCTAssertTrue(snapshot.setArchived(false, cardID: shared.id))
        XCTAssertEqual(snapshot.reviewCards(forLessonID: first.id), [new, shared])
        XCTAssertEqual(snapshot.reviewCards(forLessonID: second.id), [shared])
        XCTAssertTrue(snapshot.removeCard(id: shared.id))
        XCTAssertEqual(snapshot.lessons.map(\.cardIDs), [[], [new.id]])
        XCTAssertTrue(snapshot.schedules.isEmpty)
        XCTAssertTrue(snapshot.reviews.isEmpty)
        try snapshot.validate()
    }

    func testStaleMetadataDraftCannotOverwriteRemoteChanges() throws {
        var snapshot = LearningSnapshot()
        try snapshot.createLesson(id: id(1), title: "Исходный", course: "Курс", sourceURL: nil, createdAt: now)
        let baseline = try XCTUnwrap(snapshot.latestLesson).metadata
        let localURL = try XCTUnwrap(URL(string: "https://example.org/local"))
        let remoteURL = try XCTUnwrap(URL(string: "https://example.org/remote"))
        let original = snapshot
        let changes = [
            Lesson.Metadata(id: id(1), title: "Удалённый", course: "Курс", sourceURL: nil),
            Lesson.Metadata(id: id(1), title: "Исходный", course: "Другой", sourceURL: nil),
            Lesson.Metadata(id: id(1), title: "Исходный", course: "Курс", sourceURL: remoteURL)
        ]
        for metadata in changes {
            snapshot = original
            try snapshot.updateLesson(id: id(1), title: metadata.title, course: metadata.course, sourceURL: metadata.sourceURL)
            let remote = snapshot
            XCTAssertThrowsError(try snapshot.updateLesson(
                id: id(1),
                title: baseline.title,
                course: baseline.course,
                sourceURL: localURL,
                expectedMetadata: baseline
            )) { error in
                XCTAssertEqual(error as? LessonError, .staleMetadata)
            }
            XCTAssertEqual(snapshot, remote, "Конфликт не должен менять снимок")
        }
    }

    func testMetadataEditPreservesConcurrentMembershipAndReview() throws {
        var snapshot = LearningSnapshot()
        try snapshot.createLesson(id: id(1), title: "Исходный", course: nil, sourceURL: nil, createdAt: now)
        let baseline = try XCTUnwrap(snapshot.latestLesson).metadata
        let member = card(2)
        try snapshot.addCard(member, toLessonID: id(1))
        try CardScheduling.record(member, rating: .good, in: &snapshot, at: now)
        let remote = snapshot
        try snapshot.updateLesson(id: id(1), title: "Правка", course: nil, sourceURL: nil, expectedMetadata: baseline)
        XCTAssertEqual(snapshot.latestLesson?.title, "Правка")
        XCTAssertEqual(snapshot.latestLesson?.cardIDs, [member.id])
        XCTAssertEqual(snapshot.cards, remote.cards)
        XCTAssertEqual(snapshot.reviews, remote.reviews)
        XCTAssertEqual(snapshot.schedules, remote.schedules)
        try snapshot.removeLesson(id: id(1))
        XCTAssertThrowsError(try snapshot.updateLesson(id: id(1), title: "Правка", course: nil, sourceURL: nil, expectedMetadata: baseline))
        XCTAssertTrue(snapshot.lessons.isEmpty, "Удалённый урок не должен восстановиться")
    }

    func testCategoryOperationsAreIndependentOfCourses() throws {
        var member = card(1)
        member.deck = "Swift"
        let lesson = Lesson(id: id(2), title: "Урок", course: "Swift", sourceURL: nil, createdAt: now, cardIDs: [member.id])
        var snapshot = LearningSnapshot(cards: [member], lessons: [lesson])
        try snapshot.renameDeck(from: "Swift", to: "Новое")
        XCTAssertEqual(snapshot.cards.first?.deck, "Новое")
        XCTAssertEqual(snapshot.lessons, [lesson])
        snapshot.deleteDeck("Новое")
        XCTAssertNil(snapshot.cards.first?.deck)
        XCTAssertEqual(snapshot.lessons, [lesson])
    }
}
