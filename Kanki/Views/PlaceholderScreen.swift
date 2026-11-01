import SwiftUI

struct PlaceholderScreen: View {
    let destination: Destination

    var body: some View {
        SectionIntro(symbol: destination.symbol, title: destination.title, detail: "Это заготовка экрана. Данные и действия появятся на следующих этапах.")
            .navigationTitle(destination.title)
            .toolbarTitleDisplayMode(.inline)
    }
}
