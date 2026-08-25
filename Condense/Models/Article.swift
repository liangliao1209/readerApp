import Foundation
import SwiftData

/// 文章来源类型
enum SourceType: String, Codable, Sendable {
    case web
    case pdf
    case docx
    case pasted

    var displayName: String {
        switch self {
        case .web: return "网页"
        case .pdf: return "PDF"
        case .docx: return "Word"
        case .pasted: return "粘贴"
        }
    }
}

@Model
final class Article {

    @Attribute(.unique) var id: UUID
    var title: String
    var sourceURL: URL?
    var sourceType: SourceType
    /// 网页原文 HTML（可选，便于后续重新解析）
    var rawHTML: String?
    /// PDF / DOCX 原始文件数据
    var fileData: Data?
    /// 结构化正文段落
    var paragraphs: [String]
    /// 正文中的图片 URL（网页来源）
    var imageURLs: [String]
    var createdAt: Date
    var isArchived: Bool

    /// 各级摘要，删除文章时级联删除
    @Relationship(deleteRule: .cascade, inverse: \SummaryLevel.article)
    var summaries: [SummaryLevel]

    init(
        id: UUID = UUID(),
        title: String,
        sourceURL: URL? = nil,
        sourceType: SourceType,
        rawHTML: String? = nil,
        fileData: Data? = nil,
        paragraphs: [String],
        imageURLs: [String] = [],
        createdAt: Date = Date(),
        isArchived: Bool = false
    ) {
        self.id = id
        self.title = title
        self.sourceURL = sourceURL
        self.sourceType = sourceType
        self.rawHTML = rawHTML
        self.fileData = fileData
        self.paragraphs = paragraphs
        self.imageURLs = imageURLs
        self.createdAt = createdAt
        self.isArchived = isArchived
        self.summaries = []
    }

    /// 取某个级别的摘要文本（level 0 即全文）
    func summaryText(for level: Int) -> String? {
        if level == 0 { return paragraphs.joined(separator: "\n\n") }
        return summaries.first(where: { $0.level == level })?.text
    }

    /// 摘要是否已生成完毕（1-4 级齐全）
    var hasSummaries: Bool {
        summaries.count >= 4
    }
}
