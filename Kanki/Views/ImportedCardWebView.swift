import SwiftSoup
import SwiftUI
import WebKit

// The native WebKit adapter is the only platform-specific part of the card screen.
#if os(macOS)
private typealias WebViewRepresentable = NSViewRepresentable
#else
private typealias WebViewRepresentable = UIViewRepresentable
#endif

struct ImportedCardPage {
    enum Side {
        case question, answer
    }

    enum Status {
        case loading, ready, failed
    }

    let id = UUID()
    let side: Side
    private(set) var status: Status = .loading

    init(_ side: Side) {
        self.side = side
    }

    var canRate: Bool { side == .answer && status == .ready }

    mutating func update(id: UUID, status: Status) {
        guard id == self.id, self.status != .failed else { return }
        self.status = status
    }
}

struct ImportedCardWebView: WebViewRepresentable {
    let html: String
    let pageID: UUID
    let onLoad: (UUID, ImportedCardPage.Status) -> Void

    #if os(macOS)
    func makeNSView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    func updateNSView(_ view: WKWebView, context: Context) { context.coordinator.load(self, in: view) }
    #else
    func makeUIView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    func updateUIView(_ view: WKWebView, context: Context) { context.coordinator.load(self, in: view) }
    #endif

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func makeWebView(_ coordinator: Coordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = coordinator
        return view
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private var page: ImportedCardWebView?
        private var navigation: WKNavigation?

        func load(_ request: ImportedCardWebView, in view: WKWebView) {
            guard page?.pageID != request.pageID else { return }
            page = request
            navigation = view.loadHTMLString(request.html, baseURL: nil)
            if navigation == nil {
                // Report after the representable update so SwiftUI can safely change state.
                Task { @MainActor in request.onLoad(request.pageID, .failed) }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            complete(navigation, status: .ready)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
            complete(navigation, status: .failed)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error) {
            complete(navigation, status: .failed)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            navigation = nil
            if let page { page.onLoad(page.pageID, .failed) }
        }

        private func complete(_ navigation: WKNavigation?, status: ImportedCardPage.Status) {
            guard let navigation, navigation === self.navigation, let page else { return }
            self.navigation = nil
            page.onLoad(page.pageID, status)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard navigationAction.targetFrame?.isMainFrame == true,
                  navigationAction.navigationType == .other,
                  navigationAction.request.url?.absoluteString == "about:blank" else { return .cancel }
            return .allow
        }
    }
}

struct ImportedCardHTML {
    let title: String
    let question: String
    let revealed: String

    init(content: ImportedCardContent) throws {
        let allowed = try Whitelist.none()
            .addTags("p", "br", "b", "strong", "i", "em", "ul", "ol", "li", "code", "pre")
            .addAttributes("ol", "start")
        let cleaner = Cleaner(headWhitelist: nil, bodyWhitelist: allowed)
        let output = OutputSettings().prettyPrint(pretty: false)
        title = AnkiFieldText.title(content.title)
        let question = if content.question.isEmpty {
            // The server exports Title as escaped text; never interpret it as markup.
            Entities.escape(title, output)
        } else {
            try Self.clean(content.question, using: cleaner, output: output)
        }
        let answer = try Self.clean(content.answer, using: cleaner, output: output)
        self.question = Self.page(question)
        revealed = Self.page("\(question)<hr>\(answer)\(Self.relations(content.relations, output: output))")
    }

    private static func clean(_ fragment: String, using cleaner: Cleaner, output: OutputSettings) throws -> String {
        let document = try cleaner.clean(SwiftSoup.parseBodyFragment(fragment))
        // The sole allowed attribute must be a valid HTML integer, not arbitrary text.
        for list in try document.select("ol[start]") where try list.attr("start").wholeMatch(of: #/-?[0-9]+/#) == nil {
            try list.removeAttr("start")
        }
        return try document.outputSettings(output).body()?.html() ?? ""
    }

    private static func relations(_ relations: [AnkiE1Import.Relation], output: OutputSettings) -> String {
        guard !relations.isEmpty else { return "" }
        var fragment = "<p>Связи</p><ul>"
        for relation in relations {
            var text = "\(relation.kind.rawValue) → \(relation.targetUID)"
            if let note = relation.note, !note.isEmpty {
                text += ": \(note)"
            }
            fragment += "<li>\(Entities.escape(text, output))</li>"
        }
        return fragment + "</ul>"
    }

    private static func page(_ fragment: String) -> String {
        """
        <!doctype html>
        <html lang="ru">
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; form-action 'none'; base-uri 'none'">
            <style>
              :root { color-scheme: light dark; font: -apple-system-body; }
              body { margin: 20px; overflow-wrap: anywhere; white-space: pre-wrap; }
              pre { white-space: pre-wrap; }
            </style>
          </head>
          <body>\(fragment)</body>
        </html>
        """
    }
}
