import XCTest
@testable import Roam

final class LinkReaderTests: XCTestCase {
    @MainActor func testShareTextFindsOriginalURLWithToken() {
        XCTAssertEqual(LinkReader.firstURL(in: "富士山攻略 https://xhslink.com/a/abc?xsec_token=hello 复制打开小红书")?.absoluteString, "https://xhslink.com/a/abc?xsec_token=hello")
        XCTAssertNil(LinkReader.firstURL(in: "普通备忘"))
    }
    func testMetadataAndEntities() {
        let parsed = LinkHTML.parse("""
        <title>fallback</title>
        <meta content='富士山 &amp; 湖泊' property='og:title'>
        <meta name="description" content="路线 &quot;河口湖&quot;">
        <meta name="author" content="旅行者">
        """)
        XCTAssertEqual(parsed.title, "富士山 & 湖泊")
        XCTAssertEqual(parsed.summary, "路线 \"河口湖\"")
        XCTAssertEqual(parsed.author, "旅行者")
    }
    func testStructuredBodyPreferredToExcerpt() {
        let parsed = LinkHTML.parse("""
        <meta name="description" content="摘要">
        <script type="application/ld+json">{"@graph":[{"headline":"京都","articleBody":"第一天游览寺院。第二天去宇治。","author":{"name":"作者"}}]}</script>
        """)
        XCTAssertEqual(parsed.summary, "第一天游览寺院。第二天去宇治。")
        XCTAssertEqual(parsed.title, "京都")
        XCTAssertEqual(parsed.author, "作者")
    }
    func testArticleFallback() {
        let parsed = LinkHTML.parse("<article><p>第一天 <b>东京</b></p><p>第二天京都</p></article>")
        XCTAssertTrue(parsed.summary.contains("第二天京都"))
        XCTAssertFalse(parsed.summary.contains("<b>"))
    }
    @MainActor func testPreviewPersistsThroughArchiveAndOldNotesDecode() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("trips.json")
        let store = TravelStore(file: file, reset: true)
        let trip = try XCTUnwrap(store.trips.first), day = try XCTUnwrap(trip.days.first)
        var note = CollectedNote(title: "旧标题", text: "https://xhslink.com/a/test")
        note.preview = LinkPreview(originalURL: URL(string: note.text)!, title: "富士山", summary: "旅行内容", author: "作者", fetchedAt: Date())
        XCTAssertTrue(store.importCollectedNote(note, tripID: trip.id, dayID: day.id))
        let restored = TravelStore(file: file)
        let item = try XCTUnwrap(restored.trips[0].days[0].items.first { $0.id == note.id })
        XCTAssertEqual(item.linkPreview, note.preview)
        XCTAssertEqual(item.title, "富士山")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
        object.removeValue(forKey: "linkPreview")
        let old = try JSONDecoder().decode(PlanItem.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.linkPreview)
    }
}
