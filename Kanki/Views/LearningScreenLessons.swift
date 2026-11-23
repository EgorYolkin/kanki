import SwiftUI

extension LearningScreen {
    @ViewBuilder
    var lessonHomeSection: some View {
        if let latest = snapshot.latestLesson {
            Section {
                Button { selectedLessonID = latest.id } label: {
                    Label {
                        VStack(alignment: .leading) {
                            Text(latest.title).font(.headline)
                            Text(latest.course ?? Lesson.noCourseTitle).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "book")
                    }
                }
                .accessibilityLabel("\(latest.title) · \(latest.course ?? Lesson.noCourseTitle)")
                .accessibilityIdentifier("lessonLatest")
                LessonReviewControls(activeCount: snapshot.reviewCards(forLessonID: latest.id).count) {
                    startLessonReview(latest.id)
                }
                NavigationLink(value: LessonCatalogRoute.catalog) {
                    Label("Все уроки", systemImage: "books.vertical")
                }
                .accessibilityIdentifier("lessonCatalog")
            } header: {
                Label("Последний урок", systemImage: "clock")
            }
        } else {
            Section {
                Button("Создать урок", systemImage: "plus") { isCreatingLesson = true }
                    .accessibilityIdentifier("lessonCreate")
            } header: {
                Label("Уроки", systemImage: "books.vertical")
            }
        }
    }

    @ViewBuilder
    func lessonCatalogDestination(_ route: LessonCatalogRoute) -> some View {
        switch route {
        case .catalog:
            LessonCatalogScreen(snapshot: $snapshot) { selectedLessonID = $0 }
        case .course(let course):
            CourseLessonsScreen(snapshot: $snapshot, course: course) { selectedLessonID = $0 }
        }
    }

    var lessonCreationSheet: some View {
        LessonFormScreen(snapshot: $snapshot, onSave: createLesson) { selectedLessonID = $0 }
    }

    private func createLesson(_ draft: LessonDraft) throws {
        let id = UUID()
        var updated = snapshot
        try updated.createLesson(
            id: id,
            title: draft.normalizedTitle,
            course: draft.normalizedCourse,
            sourceURL: draft.sourceURL,
            createdAt: Date()
        )
        try apply(updated)
        selectedLessonID = id
    }

    func lessonDestination(_ id: UUID) -> some View {
        LessonDetailScreen(
            lessonID: id,
            snapshot: $snapshot,
            availableDecks: availableDecks,
            onSave: { draft in
                var updated = snapshot
                try updated.updateLesson(
                    id: id,
                    title: draft.normalizedTitle,
                    course: draft.normalizedCourse,
                    sourceURL: draft.sourceURL,
                    expectedMetadata: draft.originalMetadata
                )
                try apply(updated)
            },
            onAdd: { question, answer, deck in
                var updated = snapshot
                try updated.addCard(SessionCard(question: question, answer: answer, deck: deck), toLessonID: id)
                try apply(updated)
            },
            onDelete: {
                var updated = snapshot
                try updated.removeLesson(id: id)
                try apply(updated)
                selectedLessonID = nil
            },
            onOpenLesson: { selectedLessonID = $0 },
            onOpenCard: { selectedCard = $0 },
            onReview: { startLessonReview(id) }
        )
        .id(id)
    }
}
