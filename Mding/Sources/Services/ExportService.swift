import AppKit
import WebKit
import UniformTypeIdentifiers

/// PDF / HTML 내보내기 (File ▸ Export). 오프스크린 `WKWebView` 로 preview.html 셸을 로드해
/// 라이트 테마로 고정 렌더링한 뒤 각 포맷으로 저장한다. Save Panel 취소 시 아무 것도 하지 않는다.
/// 실패 시 NSAlert 로 알린다 — 성공 시에는 결과 파일 자체가 피드백이라 알럿을 띄우지 않는다.
@MainActor
enum ExportService {
    /// 오프스크린 렌더용 임의 크기 — 페이지 크기 자체는 내보내기 단계(PDF `NSPrintInfo`)가 결정한다.
    private static let renderFrame = NSRect(x: 0, y: 0, width: 800, height: 1000)

    /// 비동기 완료(렌더 → 인쇄/추출 → 파일 쓰기) 전까지 세션(웹뷰+델리게이트)이 조기 해제되지
    /// 않도록 강한 참조를 유지한다. 중간 해제는 콜백이 영영 오지 않는 무한 대기로 이어지는
    /// 가장 흔한 버그라, 완료·실패가 확정되는 시점에만 명시적으로 놓아준다.
    private static var activeSessions: [ExportSession] = []

    // MARK: - PDF

    static func exportAsPDF(_ document: DocumentViewModel) {
        guard let url = FileService.presentSavePanel(
            suggestedName: exportFileName(for: document, extension: "pdf"),
            allowedType: .pdf
        ) else { return }

        // NSPrintOperation.runModal 은 실제 NSWindow 컨텍스트가 필요하다(완전 headless 불가) —
        // 메뉴 클릭 시점의 key window 를 미리 캡처해 둔다(렌더 대기 중 창 전환 레이스 방지).
        let hostWindow = NSApp.keyWindow ?? NSApp.mainWindow

        let session = ExportSession(markdown: document.text, frame: renderFrame)
        activeSessions.append(session)

        session.start { result in
            switch result {
            case .success:
                writePDF(session: session, to: url, hostWindow: hostWindow) { success in
                    if !success { presentExportFailureAlert() }
                    activeSessions.removeAll { $0 === session }
                }
            case .failure:
                presentExportFailureAlert()
                activeSessions.removeAll { $0 === session }
            }
        }
    }

    /// A4 페이지네이션(§ 요구사항)으로 인쇄. 실패(예외적 false 반환) 시 연속 PDF 폴백으로 대체한다.
    private static func writePDF(
        session: ExportSession,
        to url: URL,
        hostWindow: NSWindow?,
        completion: @escaping (Bool) -> Void
    ) {
        guard let hostWindow else {
            // 활성 창이 전혀 없는 극단적 상황 — 페이지네이션 없이 연속 PDF로 대체.
            fallbackCreatePDF(from: session.webView, to: url, completion: completion)
            return
        }

        let printInfo = NSPrintInfo()
        let margin: CGFloat = 36
        printInfo.paperSize = NSSize(width: 595.2, height: 841.8)  // A4
        printInfo.topMargin = margin
        printInfo.bottomMargin = margin
        printInfo.leftMargin = margin
        printInfo.rightMargin = margin
        printInfo.horizontalPagination = .fit  // 페이지 폭에 맞춰 축소 — 가로 잘림 방지
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

        let operation = session.webView.printOperation(with: printInfo)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        // 창에 붙어있지 않은 웹뷰를 인쇄할 때 인쇄 뷰 프레임이 비어 있으면 빈 PDF 가 나온다 —
        // 페이지 크기로 명시 설정해야 한다(Apple Developer Forums #705138 에서 확인된 요령).
        operation.view?.frame = NSRect(origin: .zero, size: printInfo.paperSize)

        let runner = PDFPrintRunner { success in
            if success {
                completion(true)
            } else {
                fallbackCreatePDF(from: session.webView, to: url, completion: completion)
            }
            session.printRunner = nil
        }
        session.printRunner = runner  // 모달 인쇄 세션이 끝날 때까지 delegate 강한 참조 유지
        runner.run(operation, for: hostWindow)
    }

    /// `WKWebView.printOperation` 실패 시 폴백 — 페이지네이션 없는 연속 PDF(전체 콘텐츠를
    /// 한 번에 캡처)를 생성한다. macOS 26 최소 타깃이라 `createPDF` API 는 항상 사용 가능.
    private static func fallbackCreatePDF(from webView: WKWebView, to url: URL, completion: @escaping (Bool) -> Void) {
        webView.createPDF(configuration: WKPDFConfiguration()) { result in
            switch result {
            case .success(let data):
                do {
                    try data.write(to: url, options: .atomic)
                    completion(true)
                } catch {
                    completion(false)
                }
            case .failure:
                completion(false)
            }
        }
    }

    // MARK: - HTML

    static func exportAsHTML(_ document: DocumentViewModel) {
        guard let url = FileService.presentSavePanel(
            suggestedName: exportFileName(for: document, extension: "html"),
            allowedType: .html
        ) else { return }

        let session = ExportSession(markdown: document.text, frame: renderFrame)
        activeSessions.append(session)

        session.start { result in
            switch result {
            case .success:
                session.webView.evaluateJavaScript("document.getElementById('content').innerHTML") { value, error in
                    defer { activeSessions.removeAll { $0 === session } }
                    guard error == nil, let bodyHTML = value as? String else {
                        presentExportFailureAlert()
                        return
                    }
                    writeStandaloneHTML(bodyHTML: bodyHTML, title: document.displayName, to: url)
                }
            case .failure:
                presentExportFailureAlert()
                activeSessions.removeAll { $0 === session }
            }
        }
    }

    /// 번들 CSS 를 인라인해 외부 참조 없이 단독으로 열리는 standalone HTML 로 감싼다.
    private static func writeStandaloneHTML(bodyHTML: String, title: String, to url: URL) {
        guard let css = bundledCSS() else {
            presentExportFailureAlert()
            return
        }
        let escapedTitle = title
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let html = """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>\(escapedTitle)</title>
        <style>
        \(css)
        .markdown-body{box-sizing:border-box;max-width:980px;margin:0 auto;padding:32px 48px;}
        </style>
        </head>
        <body class="markdown-body">\(bodyHTML)</body>
        </html>
        """
        do {
            try Data(html.utf8).write(to: url, options: .atomic)
        } catch {
            presentExportFailureAlert()
        }
    }

    /// 문서 CSS(github-markdown-light) + 코드 하이라이트 CSS(github.min, 라이트) 를 읽어 합친다.
    /// `Preview` 는 folder reference 로 번들되어 상대 경로(`css/`)가 그대로 보존된다.
    private static func bundledCSS() -> String? {
        guard
            let docCSSURL = Bundle.main.url(forResource: "github-markdown-light", withExtension: "css", subdirectory: "Preview/css"),
            let hljsCSSURL = Bundle.main.url(forResource: "github", withExtension: "min.css", subdirectory: "Preview/css"),
            let docCSS = try? String(contentsOf: docCSSURL, encoding: .utf8),
            let hljsCSS = try? String(contentsOf: hljsCSSURL, encoding: .utf8)
        else { return nil }
        return docCSS + "\n" + hljsCSS
    }

    // MARK: - 공용

    private static func exportFileName(for document: DocumentViewModel, extension ext: String) -> String {
        var base = document.displayName
        if let dot = base.range(of: ".", options: .backwards) {
            base = String(base[..<dot.lowerBound])
        }
        return base + "." + ext
    }

    private static func presentExportFailureAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(
            localized: "Export Failed",
            comment: "Title of the alert shown when exporting the document as PDF or HTML fails"
        )
        alert.informativeText = String(
            localized: "The document couldn't be exported. Please try again.",
            comment: "Message of the alert shown when PDF/HTML export fails"
        )
        alert.runModal()
    }
}

/// 내보내기 1회 실행 동안 오프스크린 웹뷰 + 셸 로드 상태를 소유하는 컨테이너.
/// preview.html 셸을 로드하고, 라이트 테마 고정 후 문서를 렌더링해 완료를 콜백한다.
@MainActor
private final class ExportSession: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    private let markdown: String
    private var onShellReady: ((Result<Void, Error>) -> Void)?
    /// PDF 인쇄 경로에서만 쓰는 모달 인쇄 델리게이트 — 세션이 살아있는 동안 강하게 유지.
    var printRunner: PDFPrintRunner?

    init(markdown: String, frame: NSRect) {
        self.webView = WKWebView(frame: frame, configuration: WKWebViewConfiguration())
        self.markdown = markdown
        super.init()
        webView.navigationDelegate = self
    }

    /// 셸 로드 → didFinish 에서 라이트 테마 고정 + 렌더 → 완료 배리어(evaluateJavaScript) → 콜백.
    func start(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let shellURL = MarkdownRenderer.shellURL else {
            completion(.failure(ExportError.shellMissing))
            return
        }
        onShellReady = completion
        webView.loadFileURL(shellURL, allowingReadAccessTo: shellURL.deletingLastPathComponent())
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MarkdownRenderer.setTheme("light", in: webView)
        MarkdownRenderer.render(markdown, in: webView)
        // renderMarkdown 은 evaluateJavaScript 완료 시점에 이미 동기적으로 DOM 을 갱신한다 —
        // 같은 웹뷰의 evaluateJavaScript 호출은 호출 순서대로 처리되므로, 뒤이은 호출의 완료가
        // render 호출 이후를 보장하는 배리어 역할을 한다(레이아웃도 강제해 인쇄 크기 계산에 도움).
        webView.evaluateJavaScript("document.body.offsetHeight") { [weak self] _, _ in
            self?.onShellReady?(.success(()))
            self?.onShellReady = nil
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onShellReady?(.failure(error))
        onShellReady = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onShellReady?(.failure(error))
        onShellReady = nil
    }
}

/// `NSPrintOperation.runModal(for:delegate:didRun:contextInfo:)` 의 완료 콜백을 클로저로 감싼다.
/// 이 API 는 셀렉터 기반 델리게이트가 필요해 클래스로 분리했다 — 모달 인쇄 세션이 끝날
/// 때까지(비동기) 호출자가 강한 참조를 유지해야 한다(`ExportSession.printRunner`).
@MainActor
private final class PDFPrintRunner: NSObject {
    private var operation: NSPrintOperation?
    private let completion: (Bool) -> Void

    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
    }

    func run(_ operation: NSPrintOperation, for window: NSWindow) {
        self.operation = operation
        operation.runModal(
            for: window,
            delegate: self,
            didRun: #selector(printOperationDidRun(_:success:contextInfo:)),
            contextInfo: nil
        )
    }

    @objc private func printOperationDidRun(
        _ printOperation: NSPrintOperation,
        success: Bool,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        operation = nil
        completion(success)
    }
}

private enum ExportError: Error {
    case shellMissing
}
