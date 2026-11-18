import SwiftSoup
import SwiftUI
import WebKit

// The native WebKit adapter is the only platform-specific part of the card screen.
#if os(macOS)
private typealias WebViewRepresentable = NSViewRepresentable
#else
private typealias WebViewRepresentable = UIViewRepresentable
#endif

struct ImportedCardWebView: WebViewRepresentable {
    let html: String

    #if os(macOS)
    func makeNSView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    func updateNSView(_ view: WKWebView, context: Context) { context.coordinator.load(html, in: view) }
    #else
    func makeUIView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    func updateUIView(_ view: WKWebView, context: Context) { context.coordinator.load(html, in: view) }
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
        private var renderedHTML: String?

        func load(_ html: String, in view: WKWebView) {
            guard renderedHTML != html else { return }
            renderedHTML = html
            view.loadHTMLString(html, baseURL: nil)
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
    let question: String
    let revealed: String

    init(content: ImportedCardContent) throws {
        // No attributes (including href, style, src), scripts, template HTML or media enter the page.
        let allowed = try Whitelist.none().addTags("p", "br", "b", "strong", "i", "em", "ul", "ol", "li", "code", "pre")
        let output = OutputSettings().prettyPrint(pretty: false)
        let question = if content.question.isEmpty {
            // The server exports Title as escaped text; never interpret it as markup.
            try Entities.escape(Entities.unescape(content.title), output)
        } else {
            try SwiftSoup.clean(content.question, "", allowed, output) ?? ""
        }
        let answer = try SwiftSoup.clean(content.answer, "", allowed, output) ?? ""
        self.question = Self.page(question)
        revealed = Self.page("\(question)<hr>\(answer)")
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
