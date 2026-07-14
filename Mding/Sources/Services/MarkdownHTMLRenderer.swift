import Foundation
import JavaScriptCore

/// 마크다운 → 정적 HTML 변환기 (Quick Look 익스텐션용).
///
/// Quick Look 의 data-based HTML 프리뷰는 JavaScript 를 실행하지 않으므로, 앱 프리뷰 셸
/// (preview.html)이 웹뷰 안에서 수행하던 markdown-it 변환을 JavaScriptCore 로 미리 수행한다.
/// 번들 JS/CSS 는 앱과 동일한 Preview 폴더 레퍼런스를 그대로 사용해 렌더 결과를 일치시킨다.
final class MarkdownHTMLRenderer {

    enum RendererError: LocalizedError {
        case resourceMissing(String)
        case scriptFailed(String)

        var errorDescription: String? {
            switch self {
            case .resourceMissing(let name): "번들 리소스를 찾을 수 없음: \(name)"
            case .scriptFailed(let message): "JS 실행 실패: \(message)"
            }
        }
    }

    private let context: JSContext
    private let lightCSS: String
    private let darkCSS: String

    /// preview.html 의 md 구성과 동일해야 앱 프리뷰와 결과가 일치한다.
    /// (아웃라인 점프용 heading data-line 룰은 QL 에 불필요해 생략.)
    private static let bootstrapJS = """
    var md = markdownit({
      html: false,
      linkify: true,
      typographer: true,
      highlight: function (str, lang) {
        if (lang && typeof hljs !== 'undefined' && hljs.getLanguage(lang)) {
          try { return hljs.highlight(str, { language: lang }).value; } catch (e) {}
        }
        return '';
      }
    });
    if (typeof markdownitTaskLists !== 'undefined') {
      md.use(markdownitTaskLists, { enabled: false });
    }
    """

    init(scriptURLs: [URL], lightCSSURLs: [URL], darkCSSURLs: [URL]) throws {
        guard let context = JSContext() else {
            throw RendererError.scriptFailed("JSContext 생성 실패")
        }
        self.context = context

        // UMD 번들이 브라우저 전역(window/self)을 기대할 수 있어 전역 객체로 심을 깔아준다.
        try Self.evaluate("var window = this; var self = this;", named: "shim", in: context)
        for url in scriptURLs {
            let source = try String(contentsOf: url, encoding: .utf8)
            try Self.evaluate(source, named: url.lastPathComponent, in: context)
        }
        try Self.evaluate(Self.bootstrapJS, named: "bootstrap", in: context)

        lightCSS = try Self.concatenated(lightCSSURLs)
        darkCSS = try Self.concatenated(darkCSSURLs)
    }

    /// 번들의 Preview 폴더 레퍼런스(js/css)에서 표준 에셋을 찾는 편의 이니셜라이저.
    /// appex 에서는 `Bundle.main` 이 .appex 번들이고, 테스트에서는 앱 번들을 넘긴다.
    convenience init(bundle: Bundle) throws {
        func url(_ name: String, _ ext: String, _ subdirectory: String) throws -> URL {
            guard let url = bundle.url(forResource: name, withExtension: ext, subdirectory: subdirectory) else {
                throw RendererError.resourceMissing("\(subdirectory)/\(name).\(ext)")
            }
            return url
        }
        try self.init(
            scriptURLs: [
                url("markdown-it.min", "js", "Preview/js"),
                url("markdown-it-task-lists.min", "js", "Preview/js"),
                url("highlight.min", "js", "Preview/js"),
            ],
            lightCSSURLs: [
                url("github-markdown-light", "css", "Preview/css"),
                url("github.min", "css", "Preview/css"),
            ],
            darkCSSURLs: [
                url("github-markdown-dark", "css", "Preview/css"),
                url("github-dark.min", "css", "Preview/css"),
            ]
        )
    }

    /// `md.render()` 결과(본문 HTML 조각)를 반환한다.
    func renderBody(_ markdown: String) throws -> String {
        context.exception = nil
        guard let md = context.objectForKeyedSubscript("md"),
              let html = md.invokeMethod("render", withArguments: [markdown]),
              context.exception == nil,
              html.isString
        else {
            let reason = context.exception?.toString() ?? "md.render 결과가 문자열이 아님"
            throw RendererError.scriptFailed(reason)
        }
        return html.toString()
    }

    /// 완성된 단일 HTML 문서를 반환한다. 라이트/다크 CSS 는 prefers-color-scheme 미디어 쿼리로
    /// 분기하고, 배경·레이아웃 값은 preview.html 과 동일하게 유지한다.
    func renderDocument(_ markdown: String) throws -> String {
        let body = try renderBody(markdown)
        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <style>
        :root { color-scheme: light dark; }
        html, body { margin: 0; padding: 0; }
        body { background-color: #ffffff; }
        @media (prefers-color-scheme: dark) { body { background-color: #0d1117; } }
        .markdown-body {
          box-sizing: border-box;
          min-height: 100vh;
          max-width: 980px;
          margin: 0 auto;
          padding: 32px 48px;
        }
        </style>
        <style>@media (prefers-color-scheme: light) {
        \(lightCSS)
        }</style>
        <style>@media (prefers-color-scheme: dark) {
        \(darkCSS)
        }</style>
        </head>
        <body>
        <main class="markdown-body">
        \(body)
        </main>
        </body>
        </html>
        """
    }

    // MARK: - Helpers

    private static func evaluate(_ source: String, named name: String, in context: JSContext) throws {
        context.exception = nil
        context.evaluateScript(source, withSourceURL: URL(fileURLWithPath: name))
        if let exception = context.exception {
            throw RendererError.scriptFailed("\(name): \(exception.toString() ?? "unknown")")
        }
    }

    private static func concatenated(_ urls: [URL]) throws -> String {
        try urls.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
    }
}
