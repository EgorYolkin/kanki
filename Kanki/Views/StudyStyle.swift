import SwiftUI

/// Стекло принадлежит управляющему слою, а не тексту карточек.
struct StudyControlGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: 8, content: content)
        } else {
            content()
        }
    }
}

struct StudyFloatingSurface: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.08)))
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        }
    }
}

struct StudyActionStyle: ViewModifier {
    var prominent = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else if prominent {
            content.buttonStyle(.borderedProminent)
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
            .scrollContentBackground(.hidden)
            .background(.background.secondary)
            .environment(\.defaultMinListRowHeight, 56)
    }
}

struct StudyText: View {
    let text: String
    var isQuestion = false

    var body: some View {
        Text(text)
            .font(isQuestion ? .title2.weight(.semibold) : .body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 16)
            .textSelection(.enabled)
    }
}

struct StudyRatingButtons: View {
    let onRate: (RecallRating) -> Void

    var body: some View {
        StudyControlGroup {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 12) {
                ForEach(RecallRating.allCases, id: \.self) { rating in
                    Button {
                        onRate(rating)
                    } label: {
                        Text(rating.title)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .tint(rating.tint)
                    .modifier(StudyActionStyle())
                }
            }
        }
        .padding(.vertical, 8)
    }
}
