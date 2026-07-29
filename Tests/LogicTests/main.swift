import Foundation
import SwiftUI
import CoreGraphics

var failures = 0
var checks = 0

func check(_ label: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    if condition {
        print("  ok   \(label)")
    } else {
        failures += 1
        print("  FAIL \(label) \(detail())")
    }
}

// MARK: - Markdown parser

print("markdown parser")

let doc = """
# 七月帳號用量報告

兩個帳號、四台機器，7 月共 **1,284** 個 session。

> [!IMPORTANT]
> seth@ 帳號 7 日視窗已達 86%，建議把長任務排到另一個帳號。

## 分帳號用量

| 帳號 | session | 7 日 |
| --- | --- | --- |
| seth@ | 861 | 86% |
| studio@ | 423 | 39% |

- [x] 拆帳號分流
- [ ] 調整自動換手門檻至 70%

```bash
oc accounts usage --window 7d --json
```

- 400 張任務：首屏 1.2s
- 分頁後 SSE refetch 要重新對齊游標

1. 先開 feature flag
2. 觀察 30 分鐘

> 這是普通引言，不是 alert。

---
"""

let blocks = MarkdownParser.parse(doc)

var headings: [(Int, String)] = []
var alerts: [MarkdownBlock.AlertKind] = []
var tables: [(header: [String], rows: [[String]])] = []
var taskItems: [MarkdownBlock.TaskItem] = []
var codeBlocks: [(String?, String)] = []
var bullets = 0
var ordered = 0
var quotes = 0
var dividers = 0
var paragraphs = 0

for block in blocks {
    switch block {
    case .heading(let level, let text): headings.append((level, text))
    case .alert(let kind, _): alerts.append(kind)
    case .table(let header, let rows, _): tables.append((header, rows))
    case .taskList(let items): taskItems += items
    case .code(let language, let source): codeBlocks.append((language, source))
    case .bulletList(let items): bullets += items.count
    case .orderedList(let items): ordered += items.count
    case .quote: quotes += 1
    case .divider: dividers += 1
    case .paragraph: paragraphs += 1
    }
}

check("h1 parsed", headings.first?.0 == 1 && headings.first?.1 == "七月帳號用量報告",
      "got \(String(describing: headings.first))")
check("h2 parsed", headings.contains { $0.0 == 2 && $0.1 == "分帳號用量" })
check("IMPORTANT alert", alerts == [.important], "got \(alerts)")
check("plain quote not an alert", quotes == 1, "got \(quotes)")
check("table header", tables.first?.header == ["帳號", "session", "7 日"],
      "got \(String(describing: tables.first?.header))")
check("table rows", tables.first?.rows.count == 2 && tables.first?.rows[0] == ["seth@", "861", "86%"],
      "got \(String(describing: tables.first?.rows))")
check("task list count", taskItems.count == 2, "got \(taskItems.count)")
check("task done flags", taskItems.map(\.isDone) == [true, false],
      "got \(taskItems.map(\.isDone))")
check("task text stripped", taskItems.first?.text == "拆帳號分流",
      "got \(String(describing: taskItems.first?.text))")
check("code fence language", codeBlocks.first?.0 == "bash",
      "got \(String(describing: codeBlocks.first?.0))")
check("code body", codeBlocks.first?.1 == "oc accounts usage --window 7d --json",
      "got \(String(describing: codeBlocks.first?.1))")
check("bullets not swallowed by task list", bullets == 2, "got \(bullets)")
check("ordered list", ordered == 2, "got \(ordered)")
check("divider", dividers == 1, "got \(dividers)")
check("paragraph", paragraphs >= 1, "got \(paragraphs)")

// Inline code inside a summary must survive.
let inline = MarkdownParser.inline("要不要把 `/api/tasks` 的全量拉取改成分頁？")
check("inline markdown non-empty", !String(inline.characters).isEmpty)
check("inline strips backticks", !String(inline.characters).contains("`"),
      "got \(String(inline.characters))")

// Nested / indented lists keep their depth.
let nested = MarkdownParser.parse("- top\n  - child\n    - grandchild")
if case .bulletList(let items) = nested.first {
    check("nested depths", items.map(\.depth) == [0, 1, 2], "got \(items.map(\.depth))")
} else {
    check("nested list parsed", false, "got \(nested.first.map { "\($0)" } ?? "nil")")
}

// A fence that never closes must not hang or drop the rest.
let unterminated = MarkdownParser.parse("```go\nfunc main() {\n")
check("unterminated fence recovers", unterminated.count == 1, "got \(unterminated.count)")

// Tables that are NOT preceded by a blank line — the shape agents actually
// emit. This used to be swallowed into the paragraph and rendered as literal
// pipes.
func tableBlocks(_ source: String) -> [(header: [String], rows: [[String]], aligns: [MarkdownBlock.ColumnAlignment])] {
    MarkdownParser.parse(source).compactMap {
        if case .table(let h, let r, let a) = $0 { return (h, r, a) }
        return nil
    }
}

let tight = """
這是說明文字
| 帳號 | session |
| --- | --- |
| seth@ | 861 |
"""
let tightTables = tableBlocks(tight)
check("table right after prose is parsed", tightTables.count == 1,
      "got \(MarkdownParser.parse(tight).count) blocks, \(tightTables.count) tables")
check("…and the prose survives as its own paragraph",
      MarkdownParser.parse(tight).contains { if case .paragraph(let t) = $0 { return t == "這是說明文字" }; return false })
check("…with the right header", tightTables.first?.header == ["帳號", "session"],
      "got \(String(describing: tightTables.first?.header))")

// Text sandwiched between two tables: the second one used to be lost.
let sandwich = """
| a | b |
| --- | --- |
| 1 | 2 |

說明
| c | d |
| --- | --- |
| 3 | 4 |
"""
check("both tables around prose survive", tableBlocks(sandwich).count == 2,
      "got \(tableBlocks(sandwich).count)")

// Alignment specifiers must reach the AST.
let aligned = tableBlocks("""
| 左 | 中 | 右 |
|:---|:---:|---:|
| a | b | c |
""")
check("column alignments parsed",
      aligned.first?.aligns == [.leading, .center, .trailing],
      "got \(String(describing: aligned.first?.aligns))")

// Pipe-less outer edges are legal GitHub markdown.
let bare = tableBlocks("""
帳號 | 用量
--- | ---
seth@ | 86%
""")
check("table without outer pipes", bare.first?.header == ["帳號", "用量"],
      "got \(String(describing: bare.first?.header))")
check("…and its row", bare.first?.rows == [["seth@", "86%"]],
      "got \(String(describing: bare.first?.rows))")

// A table as the very last thing in the document.
let trailing = tableBlocks("內文\n| k | v |\n| --- | --- |\n| a | 1 |")
check("table at end of document", trailing.count == 1 && trailing.first?.rows.count == 1,
      "got \(trailing)")

// A lone delimiter-looking line must not become a table or a divider.
let notTable = MarkdownParser.parse("| --- | --- |")
check("delimiter row alone is not a table",
      !notTable.contains { if case .table = $0 { return true }; return false })

// A prose line with a pipe, followed by something dash-shaped that does NOT
// have matching cell counts, must stay prose.
let pipeProse = MarkdownParser.parse("""
first line of a paragraph
second line has a | pipe
| - |
third line
""")
check("mismatched delimiter does not promote prose to a table",
      !pipeProse.contains { if case .table = $0 { return true }; return false },
      "got \(pipeProse)")

// A table must not swallow the block that follows it.
let afterTable = MarkdownParser.parse("""
| k | v |
| --- | --- |
| a | 1 |
- 項目一 | 帶 pipe
- 項目二
""")
check("table stops at the next block",
      tableBlocks("""
| k | v |
| --- | --- |
| a | 1 |
- 項目一 | 帶 pipe
- 項目二
""").first?.rows.count == 1,
      "got \(String(describing: tableBlocks("""
| k | v |
| --- | --- |
| a | 1 |
- 項目一 | 帶 pipe
- 項目二
""").first?.rows))")
check("…and the list survives",
      afterTable.contains { if case .bulletList(let items) = $0 { return items.count == 2 }; return false },
      "got \(afterTable)")

// Matching cell counts SHOULD still interrupt a paragraph (GFM allows it).
let legitInterrupt = tableBlocks("""
說明文字
| a | b |
| --- | --- |
| 1 | 2 |
""")
check("a well-formed table still interrupts a paragraph", legitInterrupt.count == 1,
      "got \(legitInterrupt.count)")

// MARK: - Usage window decoding

print("\nusage window (wire shape)")

func decodeWindow(_ json: String) -> UsageWindow? {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try? decoder.decode(UsageWindow.self, from: Data(json.utf8))
}

let hot = decodeWindow(#"{"used_pct":86.0,"elapsed_pct":62.0,"pace":"hot","resets_at":1753800000}"#)
check("real wire keys decode", hot?.usedPct == 86 && hot?.elapsedPct == 62,
      "got \(String(describing: hot))")
check("0..100 becomes a fraction", hot?.usedFraction == 0.86,
      "got \(String(describing: hot?.usedFraction))")
check("pace verdict read from the server", hot?.isHot == true)
check("epoch resets_at", hot?.resetsTs == 1753800000,
      "got \(String(describing: hot?.resetsTs))")

// resets_at is `any` on the wire — an ISO string must not take the whole
// monitoring snapshot down with it.
let iso = decodeWindow(#"{"used_pct":41.0,"elapsed_pct":55.0,"pace":"ok","resets_at":"2026-07-29T12:00:00Z"}"#)
check("ISO resets_at still decodes", iso != nil, "got nil")
check("…and is parsed, not dropped", (iso?.resetsTs ?? 0) > 0,
      "got \(String(describing: iso?.resetsTs))")
check("ok pace is not hot", iso?.isHot == false)

let nulls = decodeWindow(#"{"used_pct":null,"elapsed_pct":null,"pace":null,"resets_at":null}"#)
check("honest nulls survive as nil", nulls != nil && nulls?.usedPct == nil && nulls?.usedFraction == nil,
      "got \(String(describing: nulls))")

let garbage = decodeWindow(#"{"used_pct":50.0,"elapsed_pct":50.0,"pace":"ok","resets_at":{"weird":1}}"#)
check("unexpected resets_at shape degrades to nil, does not throw",
      garbage != nil && garbage?.resetsTs == nil,
      "got \(String(describing: garbage))")

// The old invented keys must NOT decode into anything.
let legacy = decodeWindow(#"{"pct":0.86,"used":10,"limit":100,"label":"Max 20x"}"#)
check("the invented keys are gone", legacy?.usedPct == nil,
      "got \(String(describing: legacy?.usedPct))")

// MARK: - Studio settings (wire shape)

print("\nstudio settings (wire shape)")

func decodeSettings(_ json: String) -> StudioSettings? {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try? decoder.decode(StudioSettings.self, from: Data(json.utf8))
}

// The real settingsDTO from server/ocserverd/wire.go.
let settings = decodeSettings("""
{"token_ttl":604800,"handover_pct":75,"codex_compaction_threshold":3,
 "outsource_max_parallel":5,"updater_receive_beta":false,"updater_auto_update":true,
 "org_name":"Hardcore Studio","owner_name":"Seth","push_contact_email":"",
 "display_theme":"office","display_language":"zh-Hant","display_wide":false}
""")
check("real settings keys decode", settings?.handoverPct == 75 && settings?.tokenTtl == 604800,
      "got \(String(describing: settings))")
check("handover threshold as a fraction", settings?.handoverFraction == 0.75,
      "got \(String(describing: settings?.handoverFraction))")
check("token ttl becomes whole days", settings?.sessionDays == 7,
      "got \(String(describing: settings?.sessionDays))")
check("studio name read", settings?.studioName == "Hardcore Studio")
check("owner name read", settings?.ownerName == "Seth")

// "" is the server's "never set" sentinel — it must not surface as a name.
let unset = decodeSettings(#"{"org_name":"","owner_name":"","display_theme":""}"#)
check("empty org name reads as unset", unset?.studioName == nil,
      "got \(String(describing: unset?.studioName))")
check("empty owner name reads as unset", unset?.ownerDisplayName == nil)

// A partial payload must not throw — the settings surface grows over time.
let partial = decodeSettings(#"{"handover_pct":60}"#)
check("partial settings decode", partial?.handoverPct == 60 && partial?.tokenTtl == nil,
      "got \(String(describing: partial))")
check("…and the fallbacks hold", partial?.sessionDays == nil)

// The invented keys must not resolve.
let invented = decodeSettings(#"{"handover_threshold":0.75,"session_days":7,"theme":"office"}"#)
check("the invented settings keys are gone",
      invented?.handoverPct == nil && invented?.tokenTtl == nil,
      "got \(String(describing: invented))")

// MARK: - SVG path parser

print("\nsvg path parser")

/// Bounding box of the parsed path, in the 24-unit viewBox space.
func box(_ d: String, viewBox: CGFloat = 24) -> CGRect {
    let rect = CGRect(x: 0, y: 0, width: viewBox, height: viewBox)
    return SVGPathParser.path(from: d, in: rect, viewBox: viewBox).boundingRect
}

func approx(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.6) -> Bool {
    abs(a - b) <= tolerance
}

// Simple line commands.
let chevron = box("m9 18 6-6-6-6")
check("chevron bounds", approx(chevron.minX, 9) && approx(chevron.maxX, 15)
        && approx(chevron.minY, 6) && approx(chevron.maxY, 18),
      "got \(chevron)")

// The inbox glyph: relative moves, arcs, H/V, and a close.
let inbox = box("M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z")
check("inbox spans the viewBox width", approx(inbox.minX, 2, 0.8) && approx(inbox.maxX, 22, 0.8),
      "got \(inbox)")
check("inbox vertical extent", approx(inbox.minY, 4, 0.8) && approx(inbox.maxY, 20, 0.8),
      "got \(inbox)")

// Arc-heavy path (the gear) must stay inside the viewBox.
let gear = box("M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09a1.65 1.65 0 0 0-1-1.51 1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09a1.65 1.65 0 0 0 1.51-1 1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1Z")
check("gear inside viewBox", gear.minX >= -0.5 && gear.minY >= -0.5
        && gear.maxX <= 24.5 && gear.maxY <= 24.5,
      "got \(gear)")
check("gear is large", gear.width > 15 && gear.height > 15, "got \(gear)")

// A large-arc flag pair with no separators must parse (`a2 2 0 1 1 ...`).
let largeArc = box("M12 2a10 10 0 1 1 0 20a10 10 0 1 1 0-20z")
check("large-arc circle bounds", approx(largeArc.minY, 2, 0.8) && approx(largeArc.maxY, 22, 0.8),
      "got \(largeArc)")
check("large-arc circle width", approx(largeArc.width, 20, 1.0), "got \(largeArc)")

// H / V / relative pairs.
let hv = box("M2 2H10V10H2Z")
check("H/V rect", approx(hv.minX, 2) && approx(hv.maxX, 10)
        && approx(hv.minY, 2) && approx(hv.maxY, 10),
      "got \(hv)")

// Implicit lineto repetition after a moveto.
let implicit = box("M2 2 10 2 10 10")
check("implicit lineto", approx(implicit.maxX, 10) && approx(implicit.maxY, 10),
      "got \(implicit)")

// Scaling into a smaller frame must be uniform and centred.
let scaled = SVGPathParser.path(from: "M0 0H24V24H0Z",
                                in: CGRect(x: 0, y: 0, width: 48, height: 48),
                                viewBox: 24).boundingRect
check("uniform scale to 48pt", approx(scaled.width, 48, 0.1) && approx(scaled.height, 48, 0.1),
      "got \(scaled)")

// MARK: - Duration formatting

print("\nduration formatting")

check("42 minutes", OCFormat.duration(42 * 60) == "42 分", OCFormat.duration(42 * 60))
check("1h35m", OCFormat.duration(95 * 60) == "1 小時 35 分", OCFormat.duration(95 * 60))
check("exact hour", OCFormat.duration(3600) == "1 小時", OCFormat.duration(3600))
check("3d2h", OCFormat.duration((3 * 24 + 2) * 3600) == "3 天 2 小時",
      OCFormat.duration((3 * 24 + 2) * 3600))
check("exact day", OCFormat.duration(24 * 3600) == "1 天", OCFormat.duration(24 * 3600))
check("under a minute", OCFormat.duration(20) == "剛剛", OCFormat.duration(20))
check("negative clamps", OCFormat.duration(-100) == "剛剛", OCFormat.duration(-100))
check("percent", OCFormat.percent(0.856) == "86%", OCFormat.percent(0.856))
check("percent nil", OCFormat.percent(nil) == "—", OCFormat.percent(nil))

// MARK: - Summary

print("\n\(checks - failures)/\(checks) checks passed")
if failures > 0 {
    print("\(failures) FAILED")
    exit(1)
}
