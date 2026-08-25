import Foundation
import SwiftData

/// 压缩级别：0=全文 1=章节要点 2=段落摘要 3=三句话 4=一句话
@Model
final class SummaryLevel {

    var level: Int
    var text: String
    var createdAt: Date
    var article: Article?

    /// 各级别的中文标签
    static let labels = ["全文", "章节要点", "段落摘要", "三句话", "一句话"]

    init(level: Int, text: String, article: Article? = nil) {
        self.level = level
        self.text = text
        self.createdAt = Date()
        self.article = article
    }

    static func label(for level: Int) -> String {
        guard labels.indices.contains(level) else { return "全文" }
        return labels[level]
    }
}
