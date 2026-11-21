import SwiftUI

enum LessonCatalogRoute: Hashable {
    case catalog
    case course(String?)
}

struct LessonCatalogScreen: View {
    @Binding var snapshot: LearningSnapshot
    let onOpen: (UUID) -> Void
    @State private var query = ""

    var body: some View {
        List {
            if query.isEmpty {
                ForEach(snapshot.courseNames, id: \.self) { name in
                    courseLink(name)
                }
                if !snapshot.lessons(inCourse: nil).isEmpty {
                    courseLink(nil)
                }
            } else {
                let matches = snapshot.matchingLessons(query)
                if matches.isEmpty {
                    Text("Уроки не найдены").foregroundStyle(.secondary)
                }
                ForEach(matches) { lesson in
                    Button("\(lesson.title) · \(lesson.course ?? Lesson.noCourseTitle)", systemImage: "book") {
                        onOpen(lesson.id)
                    }
                }
            }
        }
        .navigationTitle("Все уроки")
        .toolbarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Поиск урока или курса")
    }

    private func courseLink(_ name: String?) -> some View {
        NavigationLink(value: LessonCatalogRoute.course(name)) {
            Label(name ?? Lesson.noCourseTitle, systemImage: name == nil ? "tray" : "folder")
        }
    }
}

struct CourseLessonsScreen: View {
    @Binding var snapshot: LearningSnapshot
    let course: String?
    let onOpen: (UUID) -> Void

    var body: some View {
        List(snapshot.lessons(inCourse: course)) { lesson in
            Button(lesson.title, systemImage: "book") { onOpen(lesson.id) }
        }
        .navigationTitle(course ?? Lesson.noCourseTitle)
        .toolbarTitleDisplayMode(.inline)
    }
}
