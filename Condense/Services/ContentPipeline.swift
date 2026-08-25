import Foundation
import SwiftData

/// 统一的内容输入（来自分享面板、剪贴板等）
struct SharedInput: Sendable {
    enum Kind: String, Sendable {
        case url, text, pdf, docx
    }
    var kind: Kind
    /// URL 字符串或纯文本内容
    var text: String?
    /// App Group 收件箱中的文件名（文件类输入）
    var fileName: String?
}

enum PipelineError: LocalizedError {
    case emptyContent
    case missingFile

    var errorDescription: String? {
        switch self {
        case .emptyContent: return "没有可导入的内容"
        case .missingFile: return "分享的文件不存在或已被清理"
        }
    }
}

/// 内容流水线：统一入口，按类型分发提取，存库并触发摘要预生成
@Observable
@MainActor
final class ContentPipeline {

    @ObservationIgnored private let modelContext: ModelContext
    @ObservationIgnored private lazy var summarizer = SummarizerService(context: modelContext)

    /// UI 可观察的导入状态
    var isImporting = false
    var lastError: String?

    init(context: ModelContext) {
        self.modelContext = context
    }

    /// 统一入口
    @discardableResult
    func ingest(_ input: SharedInput) async throws -> Article {
        isImporting = true
        defer { isImporting = false }

        let article: Article
        switch input.kind {
        case .url:
            guard let text = input.text, let url = URL(string: text),
                  url.scheme?.hasPrefix("http") == true else {
                throw PipelineError.emptyContent
            }
            let extracted = try await WebArticleExtractor.extract(url: url)
            article = Article(
                title: extracted.title,
                sourceURL: url,
                sourceType: .web,
                rawHTML: extracted.rawHTML,
                paragraphs: extracted.paragraphs,
                imageURLs: extracted.imageURLs
            )

        case .text:
            guard let text = input.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                throw PipelineError.emptyContent
            }
            // 粘贴的内容若本身就是一个 URL，则按网页处理
            if !text.contains("\n"), let url = URL(string: text),
               url.scheme?.hasPrefix("http") == true {
                return try await ingest(SharedInput(kind: .url, text: text))
            }
            let paragraphs = Self.splitParagraphs(text)
            article = Article(
                title: paragraphs.first.map { String($0.prefix(30)) } ?? "粘贴的文本",
                sourceType: .pasted,
                paragraphs: paragraphs
            )

        case .pdf, .docx:
            guard let name = input.fileName,
                  let fileURL = SharedInbox.fileURL(for: name) else {
                throw PipelineError.missingFile
            }
            let data = try Data(contentsOf: fileURL)
            // 读取后清理收件箱文件
            defer { try? FileManager.default.removeItem(at: fileURL) }
            let doc = try DocumentExtractor.extract(
                data: data,
                type: input.kind == .pdf ? .pdf : .docx,
                fileName: name
            )
            article = Article(
                title: doc.title,
                sourceType: input.kind == .pdf ? .pdf : .docx,
                fileData: data,
                paragraphs: doc.paragraphs
            )
        }

        modelContext.insert(article)
        try modelContext.save()

        // 后台预生成各级摘要（不阻塞导入流程）
        Task { await summarizer.generateSummaries(for: article) }
        return article
    }

    /// 拉取 Share Extension 写入共享容器的待处理分享
    func pullSharedInbox() async {
        for item in SharedInbox.pullAll() {
            let input = SharedInput(
                kind: SharedInput.Kind(rawValue: item.manifest.kind.rawValue) ?? .text,
                text: item.manifest.text,
                fileName: item.manifest.fileName
            )
            do {
                _ = try await ingest(input)
            } catch {
                lastError = error.localizedDescription
            }
            // 无论成功与否都移除清单，避免重复处理
            SharedInbox.remove(item.url)
        }
    }

    static func splitParagraphs(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
