import Foundation
import LinkPresentation
import UIKit

@MainActor
enum LinkReader {
    static func firstURL(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        return detector?.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url).first { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
    }
    nonisolated private static func fetchHTML(_ url: URL) async throws -> (String?, URL?) {
        var request = URLRequest(url: url, timeoutInterval: 18)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            if data.count >= 2_000_000 { break }
            data.append(byte)
        }
        return (String(data: data, encoding: .utf8), response.url)
    }
    static func read(_ url: URL, fallback: String) async -> LinkPreview {
        var preview = LinkPreview(originalURL: url, title: fallback, fetchedAt: Date())
        do {
            let (html, resolvedURL) = try await fetchHTML(url)
            preview.resolvedURL = resolvedURL
            if let html {
                let parsed = LinkHTML.parse(html)
                if !parsed.title.isEmpty { preview.title = parsed.title }
                preview.summary = parsed.summary
                preview.author = parsed.author
            }
        } catch { preview.failure = AppLocalization.text("暂时读不到内容，可重试或打开原文查看。") }
        if Task.isCancelled { return preview }
        let provider = LPMetadataProvider()
        provider.timeout = 12
        do {
            let metadata = try await provider.startFetchingMetadata(for: url)
            if preview.title == fallback, let title = metadata.title, !title.isEmpty { preview.title = title }
            if let imageProvider = metadata.imageProvider, imageProvider.canLoadObject(ofClass: UIImage.self) {
                let image: UIImage? = await withCheckedContinuation { continuation in
                    _ = imageProvider.loadObject(ofClass: UIImage.self) { value, _ in continuation.resume(returning: value as? UIImage) }
                }
                if let image, image.size.width > 0, image.size.height > 0 {
                    let scale = min(1, 600 / max(image.size.width, image.size.height))
                    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                    let format = UIGraphicsImageRendererFormat(); format.scale = 1
                    let data = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }.jpegData(compressionQuality: 0.72)
                    if let data, data.count <= 400_000 { preview.imageData = data }
                }
            }
        } catch { /* The original link and any HTML metadata remain available. */ }
        let blocked = ["安全验证", "访问验证", "页面不存在", "访问受限", "登录小红书"].contains { preview.title.contains($0) }
        if blocked { preview.title = fallback; preview.summary = ""; preview.imageData = nil }
        if preview.summary.isEmpty { preview.failure = AppLocalization.text("该网页未提供可读取的正文或摘要，请打开原文查看。") }
        else { preview.failure = nil }
        return preview
    }
}

enum LinkHTML {
    struct Result { var title = ""; var summary = ""; var author = "" }
    static func matches(_ pattern: String, _ text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            guard let range = Range($0.range(at: 1), in: text) else { return nil }; return String(text[range])
        }
    }
    static func clean(_ value: String) -> String {
        var text = value.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (from, to) in [("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] { text = text.replacingOccurrences(of: from, with: to) }
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func parse(_ html: String) -> Result {
        var meta: [String: String] = [:]
        for tag in matches("(<meta\\b[^>]*>)", html) {
            var attributes: [String: String] = [:]
            let expression = try! NSRegularExpression(pattern: #"([\w:-]+)\s*=\s*(["'])(.*?)\2"#, options: [.dotMatchesLineSeparators])
            for match in expression.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)) {
                if let key = Range(match.range(at: 1), in: tag), let value = Range(match.range(at: 3), in: tag) { attributes[String(tag[key]).lowercased()] = clean(String(tag[value])) }
            }
            if let key = attributes["property"] ?? attributes["name"], let value = attributes["content"] { meta[key.lowercased()] = value }
        }
        var result = Result(title: meta["og:title"] ?? meta["twitter:title"] ?? matches("<title[^>]*>(.*?)</title>", html).first.map(clean) ?? "", summary: meta["og:description"] ?? meta["description"] ?? meta["twitter:description"] ?? "", author: meta["author"] ?? meta["og:article:author"] ?? "")
        for script in matches(#"<script[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>(.*?)</script>"#, html) {
            guard let data = script.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            func visit(_ object: Any) {
                if let array = object as? [Any] { array.forEach(visit) }
                guard let dict = object as? [String: Any] else { return }
                if let body = dict["articleBody"] as? String, !body.isEmpty { result.summary = clean(body) }
                if result.title.isEmpty, let headline = dict["headline"] as? String { result.title = clean(headline) }
                if result.summary.isEmpty, let desc = dict["description"] as? String { result.summary = clean(desc) }
                if result.author.isEmpty, let author = dict["author"] as? [String: Any], let name = author["name"] as? String { result.author = clean(name) }
                if let graph = dict["@graph"] { visit(graph) }
            }
            visit(json)
        }
        if result.summary.isEmpty, let article = matches("<article\\b[^>]*>(.*?)</article>", html).first {
            let withoutScripts = article.replacingOccurrences(of: "<(script|style)[^>]*>.*?</\\1>", with: "", options: [.regularExpression, .caseInsensitive])
            result.summary = matches("<p\\b[^>]*>(.*?)</p>", withoutScripts).map(clean).filter { !$0.isEmpty }.joined(separator: "\n")
        }
        result.title = String(result.title.prefix(200)); result.summary = String(result.summary.prefix(12_000)); result.author = String(result.author.prefix(100))
        return result
    }
}
