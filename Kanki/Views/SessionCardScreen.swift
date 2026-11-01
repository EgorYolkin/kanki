import SwiftUI

struct SessionCardScreen: View {
    let card: SessionCard
    @State private var isAnswerVisible = false
    @State private var didSubmitRating = false
    @Environment(\.dismiss) private var dismiss
    let onReview: (RecallRating) -> Void

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
                                    onReview(rating)
                                    dismiss()
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
                Section {
                    Text("Оценка останется только в этом сеансе. Срок следующего повтора не рассчитывается.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Карточка этого сеанса")
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
    }
}
