import SwiftUI
import SwiftData
import UIKit

/// 文章库：卡片式列表，支持搜索、归档、手动粘贴导入
struct LibraryView: View {

    @Environment(ContentPipeline.self) private var pipeline
    @Query(sort: \Article.createdAt, order: .reverse) private var articles: [Article]

    @State private var searchText = ""
    @State private var importError: String?

    private var visibleArticles: [Article] {
        let active = articles.filter { !$0.isArchived }
        guard !searchText.isEmpty else { return active }
        return active.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if visibleArticles.isEmpty && searchText.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(visibleArticles) { article in
                            NavigationLink(value: article) {
                                ArticleCard(article: article)
                            }
                            .accessibilityIdentifier("articleCard")
                            .swipeActions(edge: .trailing) {
                                Button {
                                    article.isArchived = true
                                } label: {
                                    Label("归档", systemImage: "archivebox")
                                }
                                .tint(.gray)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("浓缩阅读")
            .searchable(text: $searchText, prompt: "搜索文章标题")
            .navigationDestination(for: Article.self) { article in
                ReaderView(article: article)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        pasteImport()
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                }
            }
            .overlay {
                if pipeline.isImporting {
                    ProgressView("正在导入…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .alert("导入失败", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
        }
    }

    // MARK: - 空状态引导

    private var emptyState: some View {
        ContentUnavailableView {
            Label("还没有文章", systemImage: "books.vertical")
        } description: {
            Text("在 Safari、微信、钉钉、飞书等 App 中打开分享面板，选择「浓缩阅读」即可收藏文章；\n也可以点击右上角从剪贴板粘贴链接或文本。")
        } actions: {
            Button("粘贴剪贴板内容") {
                pasteImport()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - 粘贴导入

    private func pasteImport() {
        guard let text = UIPasteboard.general.string?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty else {
            importError = "剪贴板为空，请先复制链接或文本"
            return
        }
        Task {
            do {
                _ = try await pipeline.ingest(SharedInput(kind: .text, text: text))
            } catch {
                importError = error.localizedDescription
            }
        }
    }
}

/// 列表卡片
private struct ArticleCard: View {

    let article: Article

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(article.title)
                .font(.headline)
                .lineLimit(2)

            if let preview = article.summaryText(for: 4) ?? article.paragraphs.first {
                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Label(article.sourceType.displayName, systemImage: sourceIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(article.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var sourceIcon: String {
        switch article.sourceType {
        case .web: return "globe"
        case .pdf: return "doc.richtext"
        case .docx: return "doc.text"
        case .pasted: return "doc.on.clipboard"
        }
    }
}
