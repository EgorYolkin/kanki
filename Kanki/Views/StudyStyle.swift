import SwiftUI

struct StudyActionStyle: ViewModifier {
    var prominent = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if prominent {
            if #available(iOS 26.0, macOS 26.0, *) {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.borderedProminent)
            }
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

struct StudyListStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            // Сгруппированные поверхности iOS; нативный inset-список на macOS.
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
    }
}

struct StudyText: View {
    let text: String
    var isQuestion = false

    var body: some View {
        Text(text)
            .font(isQuestion ? .title3.weight(.semibold) : .body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }
}

struct StudyRatingButtons: View {
    private static let regularColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    private static let accessibilityColumns = [GridItem(.flexible(), spacing: 8)]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let onRate: (RecallRating) -> Void

    var body: some View {
        LazyVGrid(
            columns: dynamicTypeSize.isAccessibilitySize ? Self.accessibilityColumns : Self.regularColumns,
            spacing: 8
        ) {
            ForEach(RecallRating.allCases, id: \.self) { rating in
                Button {
                    onRate(rating)
                } label: {
                    Text(rating.title)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .tint(rating.tint)
                .buttonStyle(.bordered)
            }
        }
    }
}
