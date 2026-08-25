import Foundation
import SwiftData
import FoundationModels

/// 摘要服务：封装 Foundation Models，逐级生成 1-4 级摘要；
/// 模型不可用时降级为简易截断式摘要。
@MainActor
final class SummarizerService {

    private let modelContext: ModelContext

    init(context: ModelContext) {
        self.modelContext = context
    }

    /// Foundation Models 是否可用（设备支持、Apple Intelligence 已开启、模型已就绪）
    var isModelAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        return false
    }

    /// 为文章生成 level 1-4 摘要并入库；每级 prompt 基于上一级结果继续压缩
    func generateSummaries(for article: Article) async {
        let fullText = article.paragraphs.joined(separator: "\n")
        guard !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        var levelTexts: [Int: String]
        if isModelAvailable {
            do {
                levelTexts = try await generateWithModel(article: article, fullText: fullText)
            } catch {
                // 模型调用失败时降级，保证压缩 bar 始终有内容可看
                levelTexts = fallbackSummaries(article: article)
            }
        } else {
            levelTexts = fallbackSummaries(article: article)
        }

        // 先清掉旧摘要再写入
        for old in article.summaries {
            modelContext.delete(old)
        }
        for level in 1...4 {
            guard let text = levelTexts[level],
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            modelContext.insert(SummaryLevel(level: level, text: text, article: article))
        }
        try? modelContext.save()
    }

    // MARK: - Foundation Models 路径

    private func generateWithModel(article: Article, fullText: String) async throws -> [Int: String] {
        let session = LanguageModelSession(instructions: """
            你是一名专业的中文内容编辑，负责把文章压缩成不同粒度的摘要。
            要求：忠实原文、不虚构信息、语言简洁流畅、使用与原文一致的语言。
            """)

        var result: [Int: String] = [:]

        // Foundation Models 上下文窗口有限（约 4096 tokens），长文先分段 map-reduce
        let source = try await condenseToFitContext(fullText, session: session)

        let level1 = try await respond(session, """
            请把下面这篇文章整理成「章节要点」：
            - 按原文的小标题或自然结构分节
            - 每节一个小标题，加 2-3 条要点
            - 总长度不超过原文的三分之一
            原文：
            \(source)
            """)
        result[1] = level1

        let level2 = try await respond(session, """
            请把下面的章节要点进一步压缩成「段落摘要」：
            - 3-6 个自然段，每段一句话概括一层意思
            内容：
            \(level1)
            """)
        result[2] = level2

        let level3 = try await respond(session, """
            请把下面的内容压缩成恰好三句话：
            \(level2)
            """)
        result[3] = level3

        let level4 = try await respond(session, """
            请用一句话概括下面内容的核心思想，不超过 40 字：
            \(level3)
            """)
        result[4] = level4

        return result
    }

    /// 长文分段摘要再合并，把输入控制在上下文窗口内
    private func condenseToFitContext(_ text: String, session: LanguageModelSession) async throws -> String {
        // 保守阈值：中文 1 字约 1 token，留出指令与输出空间
        let directLimit = 2800
        guard text.count > directLimit else { return text }

        let chunkSize = 1500
        var chunks: [String] = []
        var current = ""
        for paragraph in text.components(separatedBy: "\n") {
            if current.count + paragraph.count > chunkSize, !current.isEmpty {
                chunks.append(current)
                current = ""
            }
            current += paragraph + "\n"
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chunks.append(current)
        }

        var notes: [String] = []
        for chunk in chunks {
            let note = try await respond(session, """
                请提炼下面这段文字的关键信息，保留事实与观点，不超过 200 字：
                \(chunk)
                """)
            notes.append(note)
        }
        return notes.joined(separator: "\n")
    }

    /// 单次模型调用（保守使用字符串 prompt + respond(to:)）
    private func respond(_ session: LanguageModelSession, _ prompt: String) async throws -> String {
        let response = try await session.respond(to: prompt)
        return response.content
    }

    // MARK: - 降级路径：简易截断式摘要

    private func fallbackSummaries(article: Article) -> [Int: String] {
        let paragraphs = article.paragraphs
        let sentences = splitSentences(paragraphs.joined(separator: ""))

        // 章节要点 → 取前几段截断
        let level1 = paragraphs.prefix(3)
            .joined(separator: "\n")
            .truncated(to: 500)
        // 段落摘要 → 每段取首句
        let level2 = paragraphs.prefix(5)
            .compactMap { splitSentences($0).first }
            .joined(separator: "\n")
        // 三句话 → 全文前三句
        let level3 = sentences.prefix(3).joined(separator: "")
        // 一句话 → 全文首句截断
        let level4 = (sentences.first ?? paragraphs.first ?? "").truncated(to: 80)

        return [1: level1, 2: level2, 3: level3, 4: level4]
    }

    /// 按中英文句末标点切句，保留标点
    private func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if "。！？!?.…".contains(character) {
                sentences.append(current)
                current = ""
            }
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sentences.append(current)
        }
        return sentences
    }
}

private extension String {
    func truncated(to limit: Int) -> String {
        guard count > limit else { return self }
        return String(prefix(limit)) + "…"
    }
}
