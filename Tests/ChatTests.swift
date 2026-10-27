import XCTest
@testable import ClaudeRemote

final class ChatTests: XCTestCase {
    func testDecodeSocketMessages() throws {
        let sync = """
        {"type":"sync","reset":true,"chat":{"id":"ab12","name":"proj","cwd":"C:\\\\x","tool":"claude","mode":"default","status":"waiting","createdAt":"2026-10-26T12:00:00.000Z","updatedAt":"2026-10-26T12:00:00.000Z","seq":3,"preview":"hi","clients":1},
         "events":[{"id":"u1","seq":1,"kind":"user","text":"hi","files":[{"name":"a.jpg","size":3,"path":"C:\\\\a.jpg"}],"ts":"x"},
                   {"id":"p1","seq":3,"kind":"permission","requestId":"r","tool":"AskUserQuestion","title":"Hỏi bạn","status":"pending","input":{"x":[1,2]},
                    "suggestions":[{"type":"setMode"}],"questions":[{"question":"Màu?","header":"C","multiSelect":false,"options":[{"label":"Đỏ","description":""}]}]}]}
        """
        let msg = try JSONDecoder().decode(ChatSocketMessage.self, from: Data(sync.utf8))
        XCTAssertEqual(msg.chat?.status, "waiting")
        XCTAssertEqual(msg.events?.count, 2)
        XCTAssertEqual(msg.events?[0].files?.first?.name, "a.jpg")
        XCTAssertEqual(msg.events?[1].questions?.first?.options.first?.label, "Đỏ")
    }

    @MainActor
    func testApplyKeepsOrderAndUpdatesInPlace() {
        let meta = ChatMeta(id: "t\(UUID().uuidString.prefix(6))", name: "n", cwd: "/", tool: "claude", mode: "default", status: "idle", createdAt: nil, updatedAt: nil, seq: 0, preview: nil)
        let s = ChatSession(meta: meta, api: ServerAPI(baseURL: "http://127.0.0.1:1", token: "x"))
        s.apply([ChatEvent(id: "a", seq: 1, kind: "text", text: "Xin"), ChatEvent(id: "b", seq: 2, kind: "tool", title: "Đọc file")])
        s.apply([ChatEvent(id: "a", seq: 3, kind: "text", text: "Xin chào")])
        XCTAssertEqual(s.events.map(\.id), ["a", "b"])
        XCTAssertEqual(s.events[0].text, "Xin chào")
    }

    func testMarkdownInlineAndFileLinks() {
        let r = Markdown.render("# Tiêu đề\n- **đậm** và `C:\\Users\\a\\b.docx`\n```\ncode\n```\n| A | B |\n|---|---|\n| 1 | 2 |")
        let s = r.string
        XCTAssertTrue(s.contains("Tiêu đề"))
        XCTAssertFalse(s.contains("**"))
        XCTAssertTrue(s.contains("•"))
        XCTAssertTrue(s.contains("code"))
        XCTAssertTrue(s.contains("A │ B"))
        var link: URL?
        r.enumerateAttribute(.link, in: NSRange(location: 0, length: r.length)) { v, _, _ in
            if let u = v as? URL { link = u }
        }
        XCTAssertEqual(link.flatMap { Markdown.filePath(from: $0) }, "C:\\Users\\a\\b.docx")
        XCTAssertTrue(Markdown.looksLikePath("src/app.js"))
        XCTAssertFalse(Markdown.looksLikePath("npm install"))
        XCTAssertEqual(Markdown.filePath(from: URL(string: "file:///tmp/a%20b.txt")!), "/tmp/a b.txt")
    }
}

final class SegmentTests: XCTestCase {
    func testSplitCodeBlocks() {
        let segs = Markdown.segments("Trước\n```python\nprint(1)\n\nx=2\n```\nSau\n```\nđang viết")
        XCTAssertEqual(segs, [.text("Trước"), .code(language: "python", code: "print(1)\n\nx=2"), .text("Sau"), .code(language: "", code: "đang viết")])
    }
}

final class ListFormatTests: XCTestCase {
    func testPlainPreview() {
        XCTAssertEqual(ChatRow.plain("# Tóm tắt **đậm** `x` [a.txt](file:///a.txt)"), "Tóm tắt đậm x a.txt")
        XCTAssertTrue(ChatRow.relative(Date().addingTimeInterval(-130)).contains("phút"))
    }
}

final class TableTests: XCTestCase {
    func testSplitTable() {
        let segs = Markdown.segments("Bảng:\n| Tên | Điểm | Ghi chú |\n|:---|---:|:---:|\n| **An** | 8 | a \\| b |\n| Bình | 9 |\nSau bảng")
        guard segs.count == 3, case .table(let t) = segs[1] else { return XCTFail("\(segs)") }
        XCTAssertEqual(segs[0], .text("Bảng:"))
        XCTAssertEqual(segs[2], .text("Sau bảng"))
        XCTAssertEqual(t.header, ["Tên", "Điểm", "Ghi chú"])
        XCTAssertEqual(t.aligns, [.leading, .trailing, .center])
        XCTAssertEqual(t.rows, [["**An**", "8", "a | b"], ["Bình", "9"]])
        XCTAssertEqual(t.columnCount, 3)
        XCTAssertEqual(t.tsv, "Tên\tĐiểm\tGhi chú\nAn\t8\ta | b\nBình\t9")
    }

    func testPipeLinesWithoutSeparatorStayText() {
        let segs = Markdown.segments("| chỉ một dòng |\nchữ")
        XCTAssertEqual(segs, [.text("| chỉ một dòng |\nchữ")])
    }
}

final class SlashCommandTests: XCTestCase {
    private let all = [
        SlashCommand(name: "usage", desc: "", args: nil, skill: nil),
        SlashCommand(name: "model", desc: "", args: true, skill: nil),
        SlashCommand(name: "code-review", desc: "", args: true, skill: true),
        SlashCommand(name: "context", desc: "", args: nil, skill: nil)
    ]

    func testFilter() {
        XCTAssertEqual(SlashCommand.filter(all, draft: "/").count, 4)
        XCTAssertEqual(SlashCommand.filter(all, draft: "/co").map(\.name), ["code-review", "context"])
        XCTAssertEqual(SlashCommand.filter(all, draft: "/review").map(\.name), ["code-review"])
        XCTAssertEqual(SlashCommand.filter(all, draft: "/usage"), [])
        XCTAssertEqual(SlashCommand.filter(all, draft: "/model so"), [])
        XCTAssertEqual(SlashCommand.filter(all, draft: "hi /"), [])
    }
}
