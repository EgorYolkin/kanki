import SwiftUI

struct GraphScreen: View {
    var body: some View {
        SectionIntro(symbol: "circle.hexagongrid", title: "Граф пуст", detail: "После импорта здесь будут заметка и её ближайшие связи.")
            .navigationTitle("Граф")
    }
}
