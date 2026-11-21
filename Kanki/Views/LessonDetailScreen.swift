import SwiftUI

struct LessonDetailScreen: View {
    private enum Editor: String, Identifiable {
        case metadata
        case card
        var id: Self { self }
    }

    let lessonID: UUID
    @Binding var snapshot: LearningSnapshot
    let availableDecks: [String]
    let onSave: (LessonDraft) throws -> Void
    let onAdd: (String, String, String?) throws -> Void
    let onDelete: () throws -> Void
    let onOpenLesson: (UUID) -> Void
    let onOpenCard: (SessionCard) -> Void
    let onReview: () -> Void
    @State private var editor: Editor?
    @State private var confirmingDelete = false
    @State private var deleteError: String?

    private var lesson: Lesson? {
        snapshot.lessons.first { $0.id == lessonID }
    }

    var body: some View {
        if let lesson {
            List {
                Section {
                    LabeledContent("Курс", value: lesson.course ?? Lesson.noCourseTitle)
                    if let url = lesson.sourceURL {
                        Link(destination: url) {
                            Label("Открыть видео", systemImage: "play.rectangle")
                        }
                    }
                    LessonReviewControls(activeCount: snapshot.reviewCards(forLessonID: lessonID).count, onReview: onReview)
                }
                Section {
                    Button("Добавить карточку", systemImage: "plus.rectangle") { editor = .card }
                        .accessibilityIdentifier("lessonAddCard")
                    ForEach(snapshot.cards(forLessonID: lessonID)) { card in
                        Button { onOpenCard(card) } label: {
                            HStack {
                                Label {
                                    CardQuestionPreview(source: card.question)
                                } icon: {
                                    Image(systemName: "rectangle.on.rectangle")
                                }
                                if card.isArchived {
                                    Spacer()
                                    Text("В архиве").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                        .accessibilityIdentifier("lessonCard-\(card.id.uuidString)")
                    }
                } header: {
                    Label("Карточки", systemImage: "rectangle.on.rectangle")
                }
                Section {
                    Button("Изменить урок", systemImage: "pencil") { editor = .metadata }
                        .accessibilityIdentifier("lessonEdit")
                    Button("Удалить урок", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                        .accessibilityIdentifier("lessonDelete")
                    if let deleteError { Text(deleteError).foregroundStyle(.red) }
                }
            }
            .navigationTitle(lesson.title)
            .toolbarTitleDisplayMode(.inline)
            .sheet(item: $editor) { editor in
                switch editor {
                case .metadata:
                    LessonFormScreen(snapshot: $snapshot, lesson: lesson, onSave: onSave, onOpen: onOpenLesson)
                case .card:
                    SessionCardFormScreen(availableDecks: availableDecks, lessonTitle: lesson.title) { question, answer, deck in
                        try onAdd(question, answer, deck)
                    }
                }
            }
            .alert("Удалить урок?", isPresented: $confirmingDelete) {
                Button("Отмена", role: .cancel) {}
                Button("Удалить урок", role: .destructive) {
                    do { try onDelete() } catch { deleteError = error.localizedDescription }
                }
            } message: {
                Text("Карточки и оценки останутся")
            }
        }
    }
}

struct LessonReviewControls: View {
    let activeCount: Int
    let onReview: () -> Void

    var body: some View {
        Text("Активных карточек: \(activeCount)")
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("lessonActiveCount")
        Button("Повторить урок", systemImage: "arrow.clockwise", action: onReview)
            .disabled(activeCount == 0)
            .accessibilityIdentifier("lessonReview")
        if activeCount == 0 {
            Text("В этом уроке пока нечего повторять").foregroundStyle(.secondary)
        }
    }
}
