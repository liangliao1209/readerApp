import UIKit
import UniformTypeIdentifiers

/// 分享扩展：静默处理，不弹编辑界面。
/// 从 NSItemProvider 取 URL / 文本 / 文件，写入 App Group 收件箱后直接完成。
final class ShareViewController: UIViewController {

    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        // 极简 UI：只提示「已存入浓缩阅读」
        statusLabel.text = "已存入浓缩阅读"
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await handleSharedItems() }
    }

    private func handleSharedItems() async {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem], !items.isEmpty else {
            finish()
            return
        }
        for item in items {
            for provider in item.attachments ?? [] {
                // 每个附件只按最高优先级的一种类型处理
                if await handle(provider) { break }
            }
        }
        // 短暂停留让用户看到提示
        try? await Task.sleep(nanoseconds: 600_000_000)
        finish()
    }

    /// 按优先级处理一个附件：文件 > 网页 URL > 纯文本
    private func handle(_ provider: NSItemProvider) async -> Bool {
        // 文件：PDF / DOCX（复制进收件箱）
        for (typeIdentifier, kind) in [
            ("com.adobe.pdf", SharedInbox.Manifest.Kind.pdf),
            ("org.openxmlformats.wordprocessingml.document", .docx),
        ] where provider.hasItemConformingToTypeIdentifier(typeIdentifier) {
            if let fileName = await copyIntoInbox(provider, typeIdentifier: typeIdentifier) {
                return SharedInbox.write(kind: kind, fileName: fileName)
            }
        }

        // 网页 URL
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let url = await loadURL(provider) {
            return SharedInbox.write(kind: .url, text: url.absoluteString)
        }

        // 纯文本
        if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier),
           let text = await loadText(provider) {
            return SharedInbox.write(kind: .text, text: text)
        }

        return false
    }

    // MARK: - NSItemProvider 桥接

    /// loadFileRepresentation 会把文件复制到本进程可持久访问的临时位置
    private func copyIntoInbox(_ provider: NSItemProvider, typeIdentifier: String) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _ in
                var result: String?
                if let url {
                    result = SharedInbox.copyFile(from: url)
                }
                continuation.resume(returning: result)
            }
        }
    }

    private func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                continuation.resume(returning: item as? URL)
            }
        }
    }

    private func loadText(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.text.identifier) { item, _ in
                continuation.resume(returning: item as? String)
            }
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
