import Foundation
import PDFKit
import zlib

struct ExtractedDocument: Sendable {
    var title: String
    var paragraphs: [String]
}

enum DocumentError: LocalizedError {
    case unreadablePDF
    case invalidDocx
    case emptyContent

    var errorDescription: String? {
        switch self {
        case .unreadablePDF: return "无法解析 PDF 文件"
        case .invalidDocx: return "无法解析 Word 文件"
        case .emptyContent: return "文档中没有可提取的文本"
        }
    }
}

/// 文档正文提取：PDF 走 PDFKit，DOCX 解压 document.xml 后用 XMLParser 提取
enum DocumentExtractor {

    enum DocType: Sendable {
        case pdf, docx
    }

    static func extract(data: Data, type: DocType, fileName: String) throws -> ExtractedDocument {
        switch type {
        case .pdf: return try extractPDF(data: data, fileName: fileName)
        case .docx: return try extractDOCX(data: data, fileName: fileName)
        }
    }

    // MARK: - PDF

    private static func extractPDF(data: Data, fileName: String) throws -> ExtractedDocument {
        guard let document = PDFDocument(data: data) else {
            throw DocumentError.unreadablePDF
        }
        var paragraphs: [String] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index), let text = page.string else { continue }
            paragraphs.append(contentsOf: splitParagraphs(text))
        }
        guard !paragraphs.isEmpty else { throw DocumentError.emptyContent }

        let title = (document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? fileName
        return ExtractedDocument(title: title, paragraphs: paragraphs)
    }

    // MARK: - DOCX

    private static func extractDOCX(data: Data, fileName: String) throws -> ExtractedDocument {
        guard let xmlData = unzipDocumentXML(from: data) else {
            throw DocumentError.invalidDocx
        }
        let parserDelegate = DocxTextParser()
        let parser = XMLParser(data: xmlData)
        parser.delegate = parserDelegate
        parser.shouldProcessNamespaces = false
        guard parser.parse() || !parserDelegate.paragraphs.isEmpty else {
            throw DocumentError.invalidDocx
        }
        guard !parserDelegate.paragraphs.isEmpty else {
            throw DocumentError.emptyContent
        }
        return ExtractedDocument(title: fileName, paragraphs: parserDelegate.paragraphs)
    }

    private static func splitParagraphs(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// 解析 word/document.xml：收集 w:t 文本，按 w:p 分段
private final class DocxTextParser: NSObject, XMLParserDelegate {

    private(set) var paragraphs: [String] = []
    private var current = ""
    private var inText = false

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if elementName == "w:t" || elementName.hasSuffix("}t") {
            inText = true
        } else if elementName == "w:br" || elementName.hasSuffix("}br") {
            current += "\n"
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "w:t" || elementName.hasSuffix("}t") {
            inText = false
        } else if elementName == "w:p" || elementName.hasSuffix("}p") {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                paragraphs.append(trimmed.replacingOccurrences(of: "\n", with: " "))
            }
            current = ""
        }
    }
}

// MARK: - 极简 ZIP 读取（无第三方依赖）

extension DocumentExtractor {

    /// 从 DOCX（ZIP 容器）中定位并解压 word/document.xml，支持 stored / deflate
    private static func unzipDocumentXML(from data: Data) -> Data? {
        func u16(_ offset: Int) -> Int {
            Int(data[offset]) | (Int(data[offset + 1]) << 8)
        }
        func u32(_ offset: Int) -> Int {
            u16(offset) | (u16(offset + 2) << 16)
        }

        // 从文件尾部查找 End of Central Directory 记录（PK\x05\x06）
        guard data.count > 22 else { return nil }
        var eocd = -1
        var i = data.count - 22
        while i >= 0 {
            if data[i] == 0x50, data[i + 1] == 0x4B, data[i + 2] == 0x05, data[i + 3] == 0x06 {
                eocd = i
                break
            }
            i -= 1
        }
        guard eocd >= 0 else { return nil }

        let entryCount = u16(eocd + 10)
        var offset = u32(eocd + 16) // central directory 起始偏移

        for _ in 0..<entryCount {
            guard offset + 46 <= data.count, u32(offset) == 0x0201_4B50 else { return nil }
            let method = u16(offset + 10)
            let compressedSize = u32(offset + 20)
            let uncompressedSize = u32(offset + 24)
            let nameLength = u16(offset + 28)
            let extraLength = u16(offset + 30)
            let commentLength = u16(offset + 32)
            let localOffset = u32(offset + 42)
            guard offset + 46 + nameLength <= data.count else { return nil }
            let nameData = data.subdata(in: offset + 46 ..< offset + 46 + nameLength)
            let name = String(data: nameData, encoding: .utf8) ?? ""

            if name == "word/document.xml" {
                // 解析 local file header，找到数据起点（注意 local 与 central 的 extra 长度可能不同）
                guard localOffset + 30 <= data.count, u32(localOffset) == 0x0403_4B50 else { return nil }
                let localNameLength = u16(localOffset + 26)
                let localExtraLength = u16(localOffset + 28)
                let dataStart = localOffset + 30 + localNameLength + localExtraLength
                guard dataStart + compressedSize <= data.count else { return nil }
                let payload = data.subdata(in: dataStart ..< dataStart + compressedSize)
                switch method {
                case 0: // stored
                    return payload
                case 8: // deflate
                    return inflate(payload, expectedSize: uncompressedSize)
                default:
                    return nil
                }
            }
            offset += 46 + nameLength + extraLength + commentLength
        }
        return nil
    }

    /// 解压 raw DEFLATE 数据（ZIP 压缩格式，RFC 1951）
    /// 用 zlib 的 inflateInit2(-MAX_WBITS) 处理无 zlib 头的裸 deflate 流
    private static func inflate(_ data: Data, expectedSize: Int) -> Data? {
        var stream = z_stream()
        let initStatus = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initStatus == Z_OK else { return nil }
        defer { inflateEnd(&stream) }

        // 预留空间：个别 ZIP 的未压缩尺寸字段不可靠时给 4MB 兜底
        let capacity = max(expectedSize, 4 * 1024 * 1024)
        var output = Data(count: capacity)

        let result: Int32 = data.withUnsafeBytes { srcBuffer in
            output.withUnsafeMutableBytes { dstBuffer in
                guard let src = srcBuffer.baseAddress, let dst = dstBuffer.baseAddress else {
                    return Z_BUF_ERROR
                }
                stream.next_in = UnsafeMutablePointer(mutating: src.assumingMemoryBound(to: UInt8.self))
                stream.avail_in = uInt(data.count)
                stream.next_out = dst.assumingMemoryBound(to: UInt8.self)
                stream.avail_out = uInt(capacity)
                return zlib.inflate(&stream, Z_FINISH)
            }
        }
        guard result == Z_STREAM_END || result == Z_OK else { return nil }
        output.count = capacity - Int(stream.avail_out)
        return output
    }
}
