import Foundation
import SwiftSoup

/// 网页正文提取结果
struct ExtractedArticle: Sendable {
    var title: String
    var paragraphs: [String]
    var imageURLs: [String]
    var rawHTML: String
}

enum ExtractorError: LocalizedError {
    case network
    case noContent

    var errorDescription: String? {
        switch self {
        case .network: return "网页抓取失败，请检查网络，或改用粘贴文本导入"
        case .noContent: return "未能从网页中提取正文，请改用粘贴文本导入"
        }
    }
}

/// 网页正文提取：URLSession 抓取 + SwiftSoup 做 Readability 风格解析
enum WebArticleExtractor {

    /// 伪装成移动端 Safari
    private static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    static func extract(url: URL) async throws -> ExtractedArticle {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh-Hans;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 20

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ExtractorError.network
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ExtractorError.network
        }

        let html = String(decoding: data, as: UTF8.self)
        guard let doc = try? SwiftSoup.parse(html, url.absoluteString) else {
            throw ExtractorError.noContent
        }

        // 去除干扰元素
        try? doc.select("script, style, nav, footer, header, aside, iframe, noscript, form, button").remove()

        // 微信公众号文章正文固定在 #js_content
        var container = firstElement(in: doc, css: "#js_content")
        if container == nil {
            container = bestContentContainer(in: doc)
        }
        guard let container else { throw ExtractorError.noContent }

        // 标题：og:title > <title> > 域名
        let title = firstAttr(in: doc, css: "meta[property=og:title]", attr: "content")
            ?? (try? doc.title()).flatMap { $0.isEmpty ? nil : $0 }
            ?? url.host
            ?? "未命名文章"

        // 段落：优先取 <p>，退化时按容器纯文本拆行
        var paragraphs = ((try? container.select("p"))?.array() ?? [])
            .compactMap { try? $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if paragraphs.isEmpty {
            let text = (try? container.text()) ?? ""
            paragraphs = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        guard !paragraphs.isEmpty else { throw ExtractorError.noContent }

        // 图片：兼容懒加载的 data-src（微信公众号即如此）
        let images = ((try? container.select("img"))?.array() ?? [])
            .compactMap { img -> String? in
                let src = (try? img.attr("data-src")).flatMap { $0.isEmpty ? nil : $0 }
                    ?? (try? img.attr("src")).flatMap { $0.isEmpty ? nil : $0 }
                guard let src,
                      let resolved = URL(string: src, relativeTo: url)?.absoluteURL,
                      resolved.scheme?.hasPrefix("http") == true else { return nil }
                return resolved.absoluteString
            }

        return ExtractedArticle(title: title, paragraphs: paragraphs, imageURLs: images, rawHTML: html)
    }

    // MARK: - Readability 风格正文容器打分

    /// 按文本密度给 block 元素打分，选出最可能的正文容器
    private static func bestContentContainer(in doc: Document) -> Element? {
        guard let candidates = try? doc.select("article, main, section, div") else { return nil }
        var best: Element?
        var bestScore = 0
        for element in candidates {
            let text = (try? element.text()) ?? ""
            guard text.count >= 100 else { continue }
            let pCount = (try? element.select("p"))?.size() ?? 0
            // 链接文本占比高的块（导航、推荐列表）降权
            let linkTextCount = ((try? element.select("a"))?.array() ?? [])
                .reduce(0) { $0 + ((try? $1.text()) ?? "").count }
            let score = text.count + pCount * 50 - linkTextCount
            if score > bestScore {
                bestScore = score
                best = element
            }
        }
        return best
    }

    // MARK: - 小工具

    private static func firstElement(in doc: Document, css: String) -> Element? {
        guard let elements = try? doc.select(css) else { return nil }
        return elements.first()
    }

    private static func firstAttr(in doc: Document, css: String, attr: String) -> String? {
        guard let element = firstElement(in: doc, css: css),
              let value = try? element.attr(attr),
              !value.isEmpty else { return nil }
        return value
    }
}
