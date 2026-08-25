import SwiftUI

/// 阅读页：精美排版 + 底部压缩 bar
struct ReaderView: View {

    let article: Article

    /// 0-4 之间的连续压缩值（手势驱动）
    @State private var compression: Double = 0
    /// 吸附后的整数级别
    @State private var displayedLevel = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 标题：衬线字体
                Text(article.title)
                    .font(.system(.title, design: .serif, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)

                metaRow

                Divider()

                content
                    // 级别切换时内容平滑过渡
                    .animation(.smooth(duration: 0.25), value: displayedLevel)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            // 给底部压缩 bar 留出空间
            .padding(.bottom, 140)
        }
        .overlay(alignment: .bottom) {
            CompressBar(compression: $compression, displayedLevel: $displayedLevel)
        }
        // 级别变化时轻微触觉反馈（推到顶的「一句话」也包含在内）
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: displayedLevel)
        .navigationBarTitleDisplayMode(.inline)
        // 夜间模式跟随系统（默认行为，无需额外处理）
    }

    private var metaRow: some View {
        HStack(spacing: 12) {
            Label(article.sourceType.displayName, systemImage: "tag")
            if let host = article.sourceURL?.host {
                Text(host).lineLimit(1)
            }
            Spacer()
            Text(article.createdAt, style: .date)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: - 内容区

    @ViewBuilder
    private var content: some View {
        if displayedLevel == 0 {
            fullText
        } else if let text = article.summaryText(for: displayedLevel) {
            summaryBody(text)
        } else {
            // 摘要尚未生成（模型仍在处理中）
            VStack(spacing: 12) {
                ProgressView()
                Text("摘要生成中，先为你展示降级预览…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let preview = article.paragraphs.first {
                    Text(preview)
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(.secondary)
                        .lineSpacing(8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        }
    }

    /// 全文排版：正文段落 + 图文混排
    private var fullText: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(article.paragraphs.enumerated()), id: \.offset) { index, paragraph in
                Text(paragraph)
                    .font(.system(.body, design: .serif))
                    .lineSpacing(8)
                    .fixedSize(horizontal: false, vertical: true)

                // 图片均匀穿插在段落之间
                if let imageURL = image(after: index) {
                    AsyncImage(url: URL(string: imageURL)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        case .failure:
                            EmptyView()
                        default:
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.quaternary)
                                .frame(height: 160)
                                .overlay { ProgressView() }
                        }
                    }
                }
            }
        }
    }

    /// 把图片均匀分布到段落之后
    private func image(after paragraphIndex: Int) -> String? {
        let images = article.imageURLs
        guard !images.isEmpty, !article.paragraphs.isEmpty else { return nil }
        let step = max(article.paragraphs.count / (images.count + 1), 1)
        let slot = paragraphIndex + 1
        guard slot % step == 0 else { return nil }
        let imageIndex = slot / step - 1
        guard images.indices.contains(imageIndex) else { return nil }
        return images[imageIndex]
    }

    /// 摘要排版
    private func summaryBody(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(text.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in
                if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(line)
                        .lineSpacing(8)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        // 级别越高（越短）字号略大，突出「一句话」
        .font(.system(size: displayedLevel >= 3 ? 20 : 17, design: .serif))
    }
}
