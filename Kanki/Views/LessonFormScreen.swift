import SwiftUI

struct LessonFormScreen: View {
    private enum CourseSelection: Hashable {
        case none
        case existing(String)
        case new
    }

    @Environment(\.dismiss) private var dismiss
    @Binding private var snapshot: LearningSnapshot
    private let lessonID: UUID?
    private let onSave: (LessonDraft) throws -> Void
    private let onOpen: (UUID) -> Void
    @State private var title: String
    @State private var course: CourseSelection
    @State private var newCourse = ""
    @State private var source: String
    @State private var saveError: String?

    init(
        snapshot: Binding<LearningSnapshot>,
        lesson: Lesson? = nil,
        onSave: @escaping (LessonDraft) throws -> Void,
        onOpen: @escaping (UUID) -> Void
    ) {
        _snapshot = snapshot
        lessonID = lesson?.id
        self.onSave = onSave
        self.onOpen = onOpen
        _title = State(initialValue: lesson?.title ?? "")
        _course = State(initialValue: lesson?.course.map(CourseSelection.existing) ?? .none)
        _source = State(initialValue: lesson?.sourceURL?.absoluteString ?? "")
    }

    private var draft: LessonDraft {
        let name: String?
        switch course {
        case .none: name = nil
        case .new: name = newCourse
        case .existing(let selected): name = selected
        }
        return LessonDraft(title: title, course: name, source: source)
    }

    var body: some View {
        let input = draft
        let match = snapshot.lesson(titled: input.normalizedTitle, course: input.normalizedCourse)
        let duplicate = match.flatMap { $0.id == lessonID ? nil : $0 }
        NavigationStack {
            Form {
                TextField("Название урока", text: $title)
                    .accessibilityIdentifier("lessonTitle")
                coursePicker
                TextField("Ссылка на видео (необязательно)", text: $source)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("lessonURL")
                if let error = input.validationError {
                    Text(error).foregroundStyle(.red)
                }
                if let duplicate {
                    Text("В этом курсе уже есть урок с таким названием.")
                    Button("Открыть существующий урок") {
                        dismiss()
                        onOpen(duplicate.id)
                    }
                    .accessibilityIdentifier("lessonOpenExisting")
                }
                if let saveError {
                    Text(saveError).foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(lessonID == nil ? "Новый урок" : "Изменить урок")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save(input) }
                        .disabled(input.validationError != nil || duplicate != nil)
                        .accessibilityIdentifier("lessonSave")
                }
            }
        }
        .cardSheetSize()
    }

    @ViewBuilder
    private var coursePicker: some View {
        Picker("Курс", selection: $course) {
            Text(Lesson.noCourseTitle).tag(CourseSelection.none)
            ForEach(snapshot.courseNames, id: \.self) { name in
                Text(name).tag(CourseSelection.existing(name))
            }
            Text("Новый курс…").tag(CourseSelection.new)
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("lessonCourse")
        if course == .new {
            TextField("Название курса", text: $newCourse)
                .accessibilityIdentifier("lessonNewCourse")
        }
    }

    private func save(_ input: LessonDraft) {
        do {
            try onSave(input)
            dismiss()
        } catch {
            saveError = "Не удалось сохранить урок: \(error.localizedDescription)"
        }
    }
}
