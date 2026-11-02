import SwiftUI

struct SessionCardScreen: View {
    let card: SessionCard
    let history: [SessionReview]
    @State private var isAnswerVisible = false
    @State private var didSubmitRating = false
    @State private var saveError = ""
    @State private var showSaveError = false
    @Environment(\.dismiss) private var dismiss
    let onReview: (RecallRating) throws -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Вопрос") {
                    Text(card.question)
                }
                if isAnswerVisible {
                    Section("Ответ") {
                        Text(card.answer)
                    }
                } else {
                    Button("Показать ответ") {
                        isAnswerVisible = true
                    }
                }
                if isAnswerVisible {
                    Section("Насколько легко вспомнили?") {
                        HStack(spacing: 8) {
                            ForEach(RecallRating.allCases, id: \.self) { rating in
                                Button {
                                    guard !didSubmitRating else { return }
                                    didSubmitRating = true
                                    do {
                                        try onReview(rating)
                                        dismiss()
                                    } catch {
                                        didSubmitRating = false
                                        saveError = error.localizedDescription
                                        showSaveError = true
                                    }
                                } label: {
                                    Text(rating.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(rating.tint, in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                    }
                }
                Section("История повторений") {
                    if history.isEmpty {
                        Text("Оценок пока нет")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(history.indices, id: \.self) { index in
                            let review = history[index]
                            LabeledContent(review.rating.title,
                                           value: review.reviewedAt.formatted(date: .abbreviated, time: .standard))
                        }
                    }
                }
                Section {
                    Text("Оценка сохранится на устройстве. Срок следующего повтора не рассчитывается.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Карточка")
            .toolbarTitleDisplayMode(.inline)
            .onAppear {
                isAnswerVisible = false
                didSubmitRating = false
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .alert("Не удалось сохранить оценку", isPresented: $showSaveError) {
            Button("Закрыть", role: .cancel) {}
        } message: {
            Text(saveError)
        }
    }
}
