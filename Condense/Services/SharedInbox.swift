import Foundation

/// App Group 共享收件箱：
/// Share Extension 把分享内容写入 App Group 容器的 inbox 目录，
/// 主 App 在启动 / 回到前台时拉取处理。
///
/// 注意：此文件同时被主 App 与 Share Extension 两个 target 编译，
/// 只能依赖 Foundation，不得引用 SwiftUI / SwiftData / UIKit。
enum SharedInbox {

    static let appGroupID = "group.com.condense.app.shared"

    /// 一条分享记录（manifest JSON）
    struct Manifest: Codable, Sendable {
        enum Kind: String, Codable, Sendable {
            case url, text, pdf, docx
        }
        var kind: Kind
        /// URL 字符串或纯文本
        var text: String?
        /// 收件箱内的文件名（文件类分享）
        var fileName: String?
        var sharedAt: Date
    }

    /// 收件箱目录（自动创建）
    static var inboxURL: URL? {
        guard let base = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return nil }
        let url = base.appendingPathComponent("inbox", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    // MARK: - Extension 端写入

    /// 写入一条 manifest（文本 / URL / 已复制进收件箱的文件）
    @discardableResult
    static func write(kind: Manifest.Kind, text: String? = nil, fileName: String? = nil) -> Bool {
        guard let inbox = inboxURL else { return false }
        let manifest = Manifest(kind: kind, text: text, fileName: fileName, sharedAt: Date())
        guard let data = try? JSONEncoder().encode(manifest) else { return false }
        let file = inbox.appendingPathComponent("\(UUID().uuidString).json")
        do {
            try data.write(to: file, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// 把分享进来的文件复制进收件箱，返回收件箱内文件名
    static func copyFile(from sourceURL: URL) -> String? {
        guard let inbox = inboxURL else { return nil }
        let name = "\(UUID().uuidString)-\(sourceURL.lastPathComponent)"
        let destination = inbox.appendingPathComponent(name)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            return name
        } catch {
            return nil
        }
    }

    // MARK: - 主 App 端读取

    /// 读取所有待处理 manifest，按时间排序；调用方处理后负责 remove
    static func pullAll() -> [(url: URL, manifest: Manifest)] {
        guard let inbox = inboxURL,
              let files = try? FileManager.default.contentsOfDirectory(
                  at: inbox, includingPropertiesForKeys: nil) else { return [] }
        var result: [(URL, Manifest)] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { continue }
            result.append((file, manifest))
        }
        return result.sorted { $0.1.sharedAt < $1.1.sharedAt }
    }

    /// 收件箱内文件路径
    static func fileURL(for name: String) -> URL? {
        inboxURL?.appendingPathComponent(name)
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
