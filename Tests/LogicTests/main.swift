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

// MARK: - Many-options rules

print("\nreply-card option layout")

// 1–3: everything inline, no 讀全文 row, a summary that can breathe.
for count in 1...3 {
    check("\(count) options all inline", AskOptionLayout.inlineCount(total: count) == count,
          "got \(AskOptionLayout.inlineCount(total: count))")
    check("\(count) options no overflow", AskOptionLayout.overflowCount(total: count) == 0,
          "got \(AskOptionLayout.overflowCount(total: count))")
    check("\(count) options no 讀全文", !AskOptionLayout.showsReadFullText(total: count))
    check("\(count) options summary 5 lines", AskOptionLayout.summaryLineLimit(total: count) == 5,
          "got \(AskOptionLayout.summaryLineLimit(total: count))")
}

// 4–6: still all inline, but the summary gives up its lines to make room.
for count in 4...6 {
    check("\(count) options all inline", AskOptionLayout.inlineCount(total: count) == count,
          "got \(AskOptionLayout.inlineCount(total: count))")
    check("\(count) options no overflow", AskOptionLayout.overflowCount(total: count) == 0)
    check("\(count) options show 讀全文", AskOptionLayout.showsReadFullText(total: count))
    check("\(count) options summary 3 lines", AskOptionLayout.summaryLineLimit(total: count) == 3,
          "got \(AskOptionLayout.summaryLineLimit(total: count))")
}

// 7+: first five inline, the rest folded away.
check("7 options → 5 inline", AskOptionLayout.inlineCount(total: 7) == 5,
      "got \(AskOptionLayout.inlineCount(total: 7))")
check("7 options → 2 folded", AskOptionLayout.overflowCount(total: 7) == 2,
      "got \(AskOptionLayout.overflowCount(total: 7))")
check("12 options → 7 folded", AskOptionLayout.overflowCount(total: 12) == 7,
      "got \(AskOptionLayout.overflowCount(total: 12))")

// Inline + folded always accounts for every option — nothing may go missing.
for count in 0...20 {
    let covered = AskOptionLayout.inlineCount(total: count) + AskOptionLayout.overflowCount(total: count)
    check("\(count) options fully accounted", covered == count, "covered \(covered)")
}

// The last rule fires at ten, not before.
check("9 options no nudge", !AskOptionLayout.suggestsFewerOptions(total: 9))
check("10 options nudge", AskOptionLayout.suggestsFewerOptions(total: 10))

// A card with no options must not ask for a fold.
check("0 options inline 0", AskOptionLayout.inlineCount(total: 0) == 0)
check("0 options no overflow", AskOptionLayout.overflowCount(total: 0) == 0)

// MARK: - Chat lanes

print("\nchat lanes")

let owner = "owner"

check("owner → peer is direct",
      ChatLane.classify(from: owner, to: "m-kyle", ownerId: owner) == .direct)
check("peer → owner is direct",
      ChatLane.classify(from: "m-kyle", to: owner, ownerId: owner) == .direct)
check("member → member is inter-agent",
      ChatLane.classify(from: "m-kyle", to: "m-sasha", ownerId: owner) == .interAgent)
check("member → outsource is inter-agent",
      ChatLane.classify(from: "m-kyle", to: "ow-3", ownerId: owner) == .interAgent)
// System rows have the owner on neither end, so they must be tested before the
// inter-agent rule or they land in the wrong fold.
check("system → member is system",
      ChatLane.classify(from: "system", to: "m-kyle", ownerId: owner) == .system)
check("system → owner is still system",
      ChatLane.classify(from: "system", to: owner, ownerId: owner) == .system)
// A studio whose owner id is not the literal "owner" must still recognise both.
check("custom owner id is direct",
      ChatLane.classify(from: "seth", to: "m-kyle", ownerId: "seth") == .direct)
check("literal owner stays direct under a custom id",
      ChatLane.classify(from: "owner", to: "m-kyle", ownerId: "seth") == .direct)
check("direct is not folded", !ChatLane.direct.isFolded)
check("inter-agent folds", ChatLane.interAgent.isFolded)
check("system folds", ChatLane.system.isFolded)

// Runs merge neighbours only.
check("empty transcript has no runs", ChatLane.runs(of: []).isEmpty)
let mixed: [ChatLane] = [.direct, .interAgent, .interAgent, .system, .system, .direct]
let mixedRuns = ChatLane.runs(of: mixed)
check("mixed transcript groups into 4 runs", mixedRuns.count == 4, "got \(mixedRuns.count)")
check("run 0 is one direct", mixedRuns[0] == ChatLaneRun(lane: .direct, start: 0, count: 1))
check("run 1 is two inter-agent", mixedRuns[1] == ChatLaneRun(lane: .interAgent, start: 1, count: 2))
check("run 2 is two system", mixedRuns[2] == ChatLaneRun(lane: .system, start: 3, count: 2))
check("run 3 is one direct", mixedRuns[3] == ChatLaneRun(lane: .direct, start: 5, count: 1))

// Runs must cover every row exactly once, in order — nothing may be dropped or
// duplicated, which is the failure that would silently hide messages.
let covered = mixedRuns.flatMap { Array($0.range) }
check("runs cover every index once", covered == Array(0..<mixed.count), "got \(covered)")
check("each run holds one lane",
      mixedRuns.allSatisfy { run in run.range.allSatisfy { mixed[$0] == run.lane } })

// A split lane does not merge across the message that separates it.
let split: [ChatLane] = [.interAgent, .direct, .interAgent]
let splitRuns = ChatLane.runs(of: split)
check("a separated lane stays two folds", splitRuns.count == 3, "got \(splitRuns.count)")

// One long stretch is one run.
let long = Array(repeating: ChatLane.system, count: 7)
check("7 system rows are one run",
      ChatLane.runs(of: long) == [ChatLaneRun(lane: .system, start: 0, count: 7)])

// A forced break splits a run even when the lane does not change. This is what
// keeps a day separator from being swallowed by a run that spans midnight.
let sameLane = Array(repeating: ChatLane.direct, count: 4)
let atMidnight = [false, false, true, false]
let broken = ChatLane.runs(of: sameLane, breaks: atMidnight)
check("a forced break splits one lane into two runs", broken.count == 2, "got \(broken.count)")
check("break run 0", broken[0] == ChatLaneRun(lane: .direct, start: 0, count: 2))
check("break run 1", broken[1] == ChatLaneRun(lane: .direct, start: 2, count: 2))
check("breaks still cover every index",
      broken.flatMap { Array($0.range) } == Array(0..<4))
// A break at index 0 is meaningless — a run already starts there.
check("a break at 0 changes nothing",
      ChatLane.runs(of: sameLane, breaks: [true, false, false, false])
          == [ChatLaneRun(lane: .direct, start: 0, count: 4)])
// A short breaks array must not crash or silently split.
check("a shorter breaks array is tolerated",
      ChatLane.runs(of: sameLane, breaks: [false, false])
          == [ChatLaneRun(lane: .direct, start: 0, count: 4)])
// Breaks and lane changes compose.
check("break plus lane change",
      ChatLane.runs(of: [.direct, .direct, .system, .system],
                    breaks: [false, false, false, true])
          == [ChatLaneRun(lane: .direct, start: 0, count: 2),
              ChatLaneRun(lane: .system, start: 2, count: 1),
              ChatLaneRun(lane: .system, start: 3, count: 1)])

// MARK: - Office ordering

print("\noffice chat recency")

// Only owner↔peer rows count. Kyle talking to Sasha must not float Kyle — or
// Sasha — to the top of the office list.
let routed = [
    ChatRouting(from: "owner", to: "m-kyle", ts: 100),
    ChatRouting(from: "m-kyle", to: "owner", ts: 300),
    ChatRouting(from: "m-kyle", to: "m-sasha", ts: 900),   // inter-agent, ignored
    ChatRouting(from: "m-sasha", to: "m-kyle", ts: 950),   // inter-agent, ignored
    ChatRouting(from: "system", to: "m-kyle", ts: 999),    // handover, ignored
    ChatRouting(from: "ow-7", to: "owner", ts: 200),
]
let recency = ChatLane.directRecency(routed, ownerId: "owner")
check("kyle keeps his own newest direct message", recency["m-kyle"] == 300,
      "got \(String(describing: recency["m-kyle"]))")
check("outsource peer recorded", recency["ow-7"] == 200)
check("inter-agent does not create a peer entry", recency["m-sasha"] == nil)
check("system handover does not bump the peer", recency["m-kyle"] != 999)
check("owner is never its own peer", recency["owner"] == nil)
check("only two peers seen", recency.count == 2, "got \(recency.count)")

// The owner's own outgoing message counts — a thread you just wrote in belongs
// at the top.
let ownOnly = ChatLane.directRecency(
    [ChatRouting(from: "owner", to: "m-mira", ts: 42)], ownerId: "owner")
check("an outgoing message alone ranks the peer", ownOnly["m-mira"] == 42)

// Newest wins regardless of the order rows arrive in.
let outOfOrder = ChatLane.directRecency([
    ChatRouting(from: "m-kyle", to: "owner", ts: 500),
    ChatRouting(from: "owner", to: "m-kyle", ts: 100),
], ownerId: "owner")
check("newest wins whatever the order", outOfOrder["m-kyle"] == 500)

// A custom owner id still resolves the peer correctly.
let custom = ChatLane.directRecency(
    [ChatRouting(from: "seth", to: "m-kyle", ts: 7)], ownerId: "seth")
check("custom owner id names the peer", custom["m-kyle"] == 7)

// MARK: - Long options

print("\nlong option handling")

let shortOptions = ["先加分頁，預設 50 筆", "維持全量"]
let longOptions = ["先加分頁，預設 50 筆", String(repeating: "很長的選項描述", count: 8)]

check("short options need no full list", !AskOptionLayout.hasUnreadableOption(shortOptions))
check("a long option needs the full list", AskOptionLayout.hasUnreadableOption(longOptions))
check("two short options need no door", !AskOptionLayout.needsFullList(shortOptions))
check("two options, one long, need a door", AskOptionLayout.needsFullList(longOptions))
// The overflow door still opens for a big set of short options.
check("seven short options need a door",
      AskOptionLayout.needsFullList(Array(repeating: "短", count: 7)))
check("no options need no door", !AskOptionLayout.needsFullList([]))

// MARK: - Overlong chat messages

print("\nlong message folding")

check("nothing folds before the first measurement",
      !ChatMessageClamp.isOverlong(naturalHeight: 0))
check("a normal message is left alone",
      !ChatMessageClamp.isOverlong(naturalHeight: 180))
// The slack rule: a message only a little over the cap keeps all of itself
// rather than losing two lines to a 展開 row.
check("a message just over the cap is left alone",
      !ChatMessageClamp.isOverlong(naturalHeight: ChatMessageClamp.collapsedHeight + 10))
check("a message past the slack folds",
      ChatMessageClamp.isOverlong(naturalHeight: ChatMessageClamp.foldThreshold + 1))

check("a short message gets no cap",
      ChatMessageClamp.cap(naturalHeight: 180) == nil)
check("an overlong message is capped at the collapsed height",
      ChatMessageClamp.cap(naturalHeight: 2000)
          == ChatMessageClamp.collapsedHeight)
// cap and isOverlong have to agree at every height, not just at two samples:
// the transcript's invariant is "overlong means capped, forever".
check("capping and overlong agree at every height",
      [0, 1, 100, 179, 180, 181, 320, 999, 5000].allSatisfy { height in
          let h = CGFloat(height)
          let capped = ChatMessageClamp.cap(naturalHeight: h) != nil
          return capped == ChatMessageClamp.isOverlong(naturalHeight: h)
              && (!capped
                  || ChatMessageClamp.cap(naturalHeight: h)
                      == ChatMessageClamp.collapsedHeight)
      })

// The seed decides the very first frame, before anything has been measured.
// It only has to tell long from short.
let shortReply = "好，那就先擋著，明天再看數字。"
let longReport = doc + "\n\n" + doc
check("a one-line reply is not folded on sight",
      !ChatMessageClamp.isOverlong(
          naturalHeight: ChatMessageClamp.estimatedHeight(of: shortReply)))
check("a long report is folded on sight",
      ChatMessageClamp.isOverlong(
          naturalHeight: ChatMessageClamp.estimatedHeight(of: longReport)))
check("an empty body estimates to nothing",
      ChatMessageClamp.estimatedHeight(of: "") == 0)
// Chinese takes two half-width slots. Counting characters flat would call this
// half as tall as it is and leave a wall of text unfolded.
let cjkWall = String(repeating: "這是一段很長的中文說明，講的是同一件事。\n", count: 20)
check("a wall of Chinese is folded on sight",
      ChatMessageClamp.isOverlong(naturalHeight: ChatMessageClamp.estimatedHeight(of: cjkWall)))
check("Chinese is estimated taller than the same count of latin",
      ChatMessageClamp.estimatedHeight(of: String(repeating: "中", count: 40))
          > ChatMessageClamp.estimatedHeight(of: String(repeating: "a", count: 40)))

// MARK: - Group unread dot

print("\nroster group unread")

check("no unread member leaves the tab clean", !RosterUnread.groupHasUnread([0, 0, 0]))
check("one unread member lights the tab", RosterUnread.groupHasUnread([0, 3, 0]))
check("an empty group leaves the tab clean", !RosterUnread.groupHasUnread([]))
// The dot reads the whole group. Searching narrows the visible rows down to the
// read ones, and the tab must keep its dot anyway.
let wholeGroup = [0, 2, 0]
let searchedSubset = [0]
check("the dot survives a search that hides the unread row",
      RosterUnread.groupHasUnread(wholeGroup) && !RosterUnread.groupHasUnread(searchedSubset))

// MARK: - Reply card colour

print("\nreply card tone")

check("answered turns the card green", ReplyCardTone(statusRaw: "answered") == .answered)
check("waiting keeps the card amber", ReplyCardTone(statusRaw: "waiting") == .waiting)
// A card id with no status projected must stay amber — going grey would read as
// "nothing to do here" on a card still waiting for an answer.
check("no projected status keeps the card amber", ReplyCardTone(statusRaw: nil) == .waiting)
check("expired greys the card out", ReplyCardTone(statusRaw: "expired") == .inactive)
check("an unknown status greys the card out", ReplyCardTone(statusRaw: "sleeping") == .inactive)
// Pin the literal "unknown" too, not just an arbitrary unrecognised word. The
// decoder collapses every value it cannot read to `ReplyCardStatus.unknown`, so
// "unknown" is the ONLY string the labelled surfaces ever feed for that case —
// asserting on "sleeping" alone left `AskDetailView` and `SplitRootView` free to
// turn amber-with-「—」 without a single check going red.
check("the literal unknown wire value greys out", ReplyCardTone(statusRaw: "unknown") == .inactive)

// The chat 請示 block has no status label, so grey there reads as "nothing to
// do" rather than "unknown". Anything the build cannot read must stay amber.
check("the unlabelled block keeps an unknown status amber",
      ReplyCardTone.forUnlabelledBlock(statusRaw: "unknown") == .waiting)
check("the unlabelled block keeps an empty status amber",
      ReplyCardTone.forUnlabelledBlock(statusRaw: "") == .waiting)
check("the unlabelled block keeps a status a future build adds amber",
      ReplyCardTone.forUnlabelledBlock(statusRaw: "revoked") == .waiting)
check("the unlabelled block still greys an expired card out",
      ReplyCardTone.forUnlabelledBlock(statusRaw: "expired") == .inactive)

// MARK: - Handled reply cards

print("\nhandled reply cards")

check("answered count respects its fetch cap",
      HandledReplyCardsPolicy.badgeCount(answeredTotal: 99, expiredTotal: 0) == 20)
check("expired count respects its fetch cap",
      HandledReplyCardsPolicy.badgeCount(answeredTotal: 0, expiredTotal: 99) == 10)
check("mixed count includes answered and expired",
      HandledReplyCardsPolicy.badgeCount(answeredTotal: 12, expiredTotal: 7) == 19)
check("mixed count respects both fetch caps",
      HandledReplyCardsPolicy.badgeCount(answeredTotal: 99, expiredTotal: 99) == 30)
check("a loaded pane reports the rows that actually arrived",
      HandledReplyCardsPolicy.badgeCount(
          answeredTotal: 99,
          expiredTotal: 99,
          loadedCount: 18
      ) == 18)

let replyCardRevisions = (0..<3).reduce(into: [UInt64(0)]) { revisions, _ in
    revisions.append(HandledReplyCardsPolicy.nextRevision(after: revisions.last!))
}
check("each reply-card invalidation advances the revision",
      replyCardRevisions == [0, 1, 2, 3],
      "got \(replyCardRevisions)")
check("the revision still changes when it wraps",
      HandledReplyCardsPolicy.nextRevision(after: .max) == 0)

// The no-SDK harness cannot compile StudioStore or the SwiftUI views. Keep a
// narrow source-level contract for the production wiring so the pure policy
// tests cannot stay green after somebody disconnects that policy from the app.
let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

func sourceFile(_ relativePath: String) -> String {
    let url = repositoryRoot.appendingPathComponent(relativePath)
    return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
}

/// Source with its comments removed, and with string literals blanked first.
///
/// Two lessons, both from mutants that passed: a source-level check that reads
/// comments can be defeated by one (a `// was: …` line above a direct send kept
/// the check green), and a naive comment stripper reads the `//` inside
/// "https://…" as the start of a comment and eats the rest of the line — which
/// is enough to hide a send.
func withoutComments(_ source: String) -> String {
    var blanked = ""
    var inString = false
    var escaped = false
    for character in source {
        if escaped { escaped = false; if !inString { blanked.append(character) }; continue }
        if character == "\\" && inString { escaped = true; continue }
        if character == "\"" { inString.toggle(); blanked.append("\""); continue }
        if character == "\n" { inString = false }
        blanked.append(inString ? " " : character)
    }

    var out = ""
    var rest = Substring(blanked)
    while true {
        let line = rest.range(of: "//")
        let block = rest.range(of: "/*")
        // Whichever opener comes FIRST — asking about "//" first would leave a
        // block comment unstripped whenever any line comment follows it.
        guard let opener = [line, block]
            .compactMap({ $0 })
            .min(by: { $0.lowerBound < $1.lowerBound })
        else { break }
        out += rest[rest.startIndex..<opener.lowerBound]
        if rest[opener] == "//" {
            rest = rest[(rest[opener.upperBound...].firstIndex(of: "\n") ?? rest.endIndex)...]
        } else if let close = rest[opener.upperBound...].range(of: "*/") {
            rest = rest[close.upperBound...]
        } else {
            rest = rest[rest.endIndex...]
        }
    }
    return out + rest
}

/// Source with every run of whitespace collapsed to a single space.
///
/// The checks below are about structure, not layout: `dismiss()` on the next
/// line and `dismiss()` on the same line are the same bug, and a call wrapped
/// to fit the column limit is the same call. Both of those beat the first
/// version of these checks.
func squashed(_ source: String) -> String {
    source.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

/// Every Swift file under a directory, so a check can ask "which files do X"
/// instead of naming the files it already knows about.
func swiftSources(under relativePath: String) -> [(name: String, body: String)] {
    let root = repositoryRoot.appendingPathComponent(relativePath)
    guard let walker = FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: nil
    ) else { return [] }
    return walker.compactMap { entry in
        guard let url = entry as? URL, url.pathExtension == "swift",
              let body = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return (url.lastPathComponent, squashed(withoutComments(body)))
    }
}

let studioStoreSource = sourceFile("OffiCraft/App/StudioStore.swift")
let asksViewSource = sourceFile("OffiCraft/Features/Asks/AsksView.swift")
let splitRootViewSource = sourceFile("OffiCraft/Features/iPad/SplitRootView.swift")
let chatViewSource = sourceFile("OffiCraft/Features/Office/ChatView.swift")
let collapsibleMessageBodySource =
    sourceFile("OffiCraft/Features/Office/CollapsibleMessageBody.swift")
let chatFoldedRunSource = sourceFile("OffiCraft/Features/Office/ChatFoldedRun.swift")
let attachmentPreviewSource =
    sourceFile("OffiCraft/Features/Attachments/AttachmentPreview.swift")

check("reply-card SSE invalidates the handled snapshot",
      studioStoreSource.contains("case .replyCard:\n            invalidateReplyCards()"))
check("iPhone handled pane observes reply-card revision",
      asksViewSource.contains(".onChange(of: store.replyCardRevision)"))
check("iPad handled pane observes reply-card revision",
      splitRootViewSource.contains(".onChange(of: store.replyCardRevision)"))
check("iPhone handled pane no longer observes answered totals",
      !asksViewSource.contains(".onChange(of: store.cardCounts.answered)"))
check("iPad handled pane no longer observes answered totals",
      !splitRootViewSource.contains(".onChange(of: store.cardCounts.answered)"))

// MARK: - Chat message full-text preview

print("\nchat message full-text preview")

check("overlong bubbles have no inline expanded state",
      !collapsibleMessageBodySource.contains("isExpanded")
          && collapsibleMessageBodySource.contains(
              "let onOpenFullText: () -> Void"
          ))
check("both the folded body and the full-text row open the viewer",
      collapsibleMessageBodySource.contains("onOpenFullText()")
          && collapsibleMessageBodySource.contains("if cap != nil")
          && collapsibleMessageBodySource.contains(
              "Button(action: onOpenFullText)"
          )
          && collapsibleMessageBodySource.contains("if isOverlong { openRow }"))
check("ChatView removed transcript message expansion state",
      !chatViewSource.contains("expandedMessages")
          && !chatViewSource.contains("toggleMessage"))
check("dropping a full-text call site cannot compile",
      chatViewSource.contains("let onOpenFullText: () -> Void")
          && chatFoldedRunSource.contains("let onOpenFullText: () -> Void")
          && !chatViewSource.contains("onOpenFullText: () -> Void = ")
          && !chatFoldedRunSource.contains("onOpenFullText: () -> Void = "))
check("direct and folded chat rows route full text to markdownText",
      chatViewSource.contains("preview = .markdownText(")
          && chatViewSource.components(
              separatedBy: "onOpenFullText: { openFullText(message) }"
          ).count == 3)
check("message markdown shares the existing fullscreen presenter",
      attachmentPreviewSource.contains(
          ".fullScreenCover(item: bindingForFullScreen)"
      )
          && attachmentPreviewSource.contains(
              "case markdownText(MessageMarkdownPreviewPayload)"
          )
          && attachmentPreviewSource.contains(
              "MessageMarkdownPreviewView(payload: message)"
          ))
check("message viewer renders markdown metadata and copy affordance",
      attachmentPreviewSource.contains(
          "MarkdownView(payload.source, scale: .document)"
      )
          && attachmentPreviewSource.contains("Text(payload.title)")
          && attachmentPreviewSource.contains(
              "OCFormat.time(payload.timestamp)"
          )
          && attachmentPreviewSource.contains(
              "UIPasteboard.general.string = payload.source"
          ))
check("own bubbles stay plain text in the transcript",
      chatViewSource.components(
          separatedBy: "MarkdownView(message.body, scale: .message)"
      ).count == 2
          && chatViewSource.contains("Text(message.body)")
          && chatViewSource.contains(".foregroundStyle(OC.bubbleOwnText)"))
// A bubble rendered as plain text must not become markdown one tap later.
check("the viewer inherits the bubble's own plain-text rule",
      chatViewSource.contains(
          "rendersMarkdown: !message.isOwn(ownerId: session.ownerId)"
      )
          && attachmentPreviewSource.contains("let rendersMarkdown: Bool")
          && attachmentPreviewSource.contains("if payload.rendersMarkdown {")
          && attachmentPreviewSource.contains("MarkdownView(payload.source, scale: .document)")
          && attachmentPreviewSource.contains("Text(payload.source)"))
// 完成 is the only way out of the cover — no drag-to-dismiss, no nav bar.
check("the message viewer keeps a working way out",
      attachmentPreviewSource.contains("Button { dismiss() } label:")
          && attachmentPreviewSource.contains("關閉訊息全文"))

// MARK: - iPad split navigation

print("\niPad split navigation")

check("iPad uses a direct native column visibility binding",
      splitRootViewSource.contains(
          "@State private var columnVisibility: NavigationSplitViewVisibility = .all"
      )
          && splitRootViewSource.contains(
              "NavigationSplitView(columnVisibility: $columnVisibility)"
          )
          && !splitRootViewSource.contains(
              "private var columnVisibility: Binding<NavigationSplitViewVisibility>"
          ))
check("iPad snapshots all versus double before entering detail-only",
      splitRootViewSource.contains(
          "@State private var columnVisibilityBeforeDetailOnly: "
              + "NavigationSplitViewVisibility = .all"
      )
          && splitRootViewSource.contains(
              "columnVisibility == .doubleColumn ? .doubleColumn : .all"
          )
          && splitRootViewSource.contains("requestColumnVisibility(.detailOnly)"))
check("iPad restores all columns in two view-driven render passes",
      splitRootViewSource.contains(
          "guard columnVisibilityBeforeDetailOnly == .all else"
      )
          && splitRootViewSource.contains(
              "columnVisibility = .doubleColumn\n        Task { @MainActor in"
          )
          && splitRootViewSource.components(
              separatedBy: "await Task.yield()"
          ).count == 3
          && splitRootViewSource.contains("columnVisibility = .all"))
check("iPad cancels a stale deferred all-column restoration",
      splitRootViewSource.contains("@State private var visibilityRequestGeneration = 0")
          && splitRootViewSource.contains("visibilityRequestGeneration &+= 1")
          && splitRootViewSource.contains(
              "guard requestGeneration == visibilityRequestGeneration else { return }"
          )
          && splitRootViewSource.contains(
              "private func requestColumnVisibility("
          ))
check("iPad sidebar controls write native visibility directly",
      splitRootViewSource.contains("requestColumnVisibility(.doubleColumn)")
          && splitRootViewSource.contains("requestColumnVisibility(.all)"))

let consecutiveAskSelections = ["rc-1", "rc-2", "rc-3"].map {
    IPadSplitDetailIdentity(kind: .ask, itemID: $0)
}
check("three consecutive selections have three detail identities",
      Set(consecutiveAskSelections).count == 3)
check("iPad detail stack is keyed by its selection identity",
      splitRootViewSource.contains(
          "NavigationStack { detailColumn }\n                .id(detailIdentity)"
      ))
check("iPad maps all three selected IDs into detail identity",
      splitRootViewSource.contains(
          "IPadSplitDetailIdentity(kind: .ask, itemID: selectedCardId)"
      )
          && splitRootViewSource.contains(
              "IPadSplitDetailIdentity(kind: .task, itemID: selectedTaskId)"
          )
          && splitRootViewSource.contains(
              "IPadSplitDetailIdentity(kind: .peer, itemID: selectedPeerId)"
          ))
check("iPad full-screen controls are gated on selected detail",
      splitRootViewSource.contains("if hasSelectedDetail")
          && splitRootViewSource.contains("enterDetailOnly()")
          && splitRootViewSource.contains("exitDetailOnly()"))

// MARK: - Ask pane order

print("\nask pane order")

// Tuples stand in for cards: the entity types need the iOS SDK, the rule does
// not.
let orderSample = [
    (ts: 100.0, id: "rc-a"),
    (ts: 300.0, id: "rc-b"),
    (ts: 200.0, id: "rc-c"),
]

check("the newest card leads the pane",
      ReplyCardOrder.newestFirst(orderSample) { $0 }.map(\.id)
          == ["rc-b", "rc-c", "rc-a"])
check("an older card never outranks a newer one",
      ReplyCardOrder.newestFirst([(ts: 1.0, id: "rc-old"), (ts: 2.0, id: "rc-new")]) { $0 }
          .first?.id == "rc-new")

// Same timestamp, opposite input order: without the id tiebreak these two can
// come back differently on consecutive refreshes and the list twitches.
let tied = [(ts: 5.0, id: "rc-x"), (ts: 5.0, id: "rc-y")]
check("cards sharing a timestamp keep one stable order",
      ReplyCardOrder.newestFirst(tied) { $0 }.map(\.id)
          == ReplyCardOrder.newestFirst(tied.reversed()) { $0 }.map(\.id))

// The keys decide which timestamp each pane actually reads, so they carry the
// part of the rule a comparator test cannot see.
check("待回覆 orders on when the card was opened",
      ReplyCardOrder.waitingKey(createdTs: 42, id: "rc-a").ts == 42)
check("近期已處理 prefers the answered moment",
      ReplyCardOrder.handledKey(answeredTs: 900, expiredTs: 100, id: "rc-a").ts
          == 900)
check("an expired card falls back to when it expired",
      ReplyCardOrder.handledKey(answeredTs: nil, expiredTs: 100, id: "rc-a").ts
          == 100)
check("a card with neither timestamp sorts last, not first",
      ReplyCardOrder.handledKey(answeredTs: nil, expiredTs: nil, id: "rc-a").ts
          == 0)

// The no-SDK harness cannot compile StudioStore, so this is the only guard
// against the app quietly sorting its panes some other way.
check("every pane routes its order through the shared rule",
      studioStoreSource.components(separatedBy: "ReplyCardOrder.newestFirst")
          .count == 5
          && studioStoreSource.components(
              separatedBy: "ReplyCardOrder.waitingKey(createdTs:"
          ).count == 3
          && studioStoreSource.components(
              separatedBy: "ReplyCardOrder.handledKey("
          ).count == 3)
check("no pane keeps its own inline card comparator",
      !studioStoreSource.contains(".sorted { $0.createdTs")
          && !studioStoreSource.contains(".sorted { $0.answeredTs"))

// MARK: - Answer confirmation

print("\nanswer confirmation")

let askDetailSource = sourceFile("OffiCraft/Features/Asks/AskDetailView.swift")
let taskDetailSource = sourceFile("OffiCraft/Features/Tasks/TaskDetailView.swift")

// Confirming has to be as specific as the tap it replaces: a dialog that does
// not name the option is no better than the mis-tap.
check("the dialog quotes the option it is about to send",
      AnswerConfirmationCopy.message(option: "先加分頁，預設 50 筆")
          .contains("「先加分頁，預設 50 筆」"))
check("a long option is trimmed but still identifiable",
      AnswerConfirmationCopy.preview(of: String(repeating: "選", count: 200))
          == String(repeating: "選", count: AnswerConfirmationCopy.optionPreviewLimit) + "…")
check("a short option is passed through untouched",
      AnswerConfirmationCopy.preview(of: "寄出") == "寄出")
check("an unhydrated card does not quote an empty option",
      !AnswerConfirmationCopy.message(option: "").contains("「")
          && !AnswerConfirmationCopy.message(option: "   ").contains("「"))
check("the dialog says what sending does",
      AnswerConfirmationCopy.message(option: "寄出").contains("關閉")
          && AnswerConfirmationCopy.confirm == "送出回覆")

// A per-file count of call sites cannot see a NEW screen that answers without
// the guard — and the first version of this change shipped exactly that bug in
// AskFullTextView, which no per-file check was looking at. So state the
// invariants over the whole app tree instead, and let them find the files.
let appSources = swiftSources(under: "OffiCraft")

// 1. Discovery: who can even show an option? A new screen with option rows has
// to come past this line, which is the moment to ask whether it is guarded.
let optionRowFiles = Set(
    appSources.filter { $0.body.contains("ReplyOptionRow(") }.map(\.name)
)
check("the set of screens that show reply options is unchanged",
      optionRowFiles == [
          "AskCardView.swift", "AskDetailView.swift",
          "AskFullTextView.swift", "TaskDetailView.swift",
      ],
      "got \(optionRowFiles.sorted())")

// 2. Nobody sends an option answer except through a confirmed PendingAnswer.
// Per CALL, not per file: one screen can stage on one path and still send
// directly on another, and a file-level check reads that as safe.
for source in appSources where source.name != "StudioStore.swift" {
    let calls = source.body.components(separatedBy: "store.answer(").dropFirst()
        + source.body.components(separatedBy: "api.answer(").dropFirst()
    for call in calls {
        let head = String(call.prefix(160))
        // Either it is the written-out answer (no option at all), or it sends
        // the option that came back from the dialog.
        let confirmed = head.contains("optionIdx: nil")
            || head.contains("pending.optionIdx")
        // Named outright rather than derived from a path, so the exemption
        // reads as the decision it is.
        let documentedException = source.name == "NotificationManager.swift"
        check("\(source.name) sends an option answer only after confirmation",
              confirmed || documentedException,
              "unconfirmed send: \(head.prefix(60))")
    }
}

// 3. Staging implies guarding: a screen that stages an answer must also present
// the dialog, or the answer is staged and never resolved.
for source in appSources where source.body.contains("PendingAnswer(") {
    check("\(source.name) presents the dialog it stages for",
          source.body.contains(".answerConfirmation("))
}

// 4. The all-options cover is the one that broke: it must NOT close itself on
// tap, or it takes its own confirmation dialog down with it.
// Look at the closure itself, not at one spelling of it: `dismiss()` on the
// next line, on the same line behind a semicolon, and as `self.dismiss()` are
// the same bug, and the first two both beat an earlier version of this check.
check("the all-options cover leaves closing to its caller",
      squashed(withoutComments(
          sourceFile("OffiCraft/Features/Asks/AskFullTextView.swift")
      ))
      .components(separatedBy: "onAnswer(index)")
      .dropFirst()
      .allSatisfy { tail in
          !String(tail.prefix(while: { $0 != "}" })).contains("dismiss")
      })
check("both callers close the cover only after the send is confirmed",
      squashed(withoutComments(asksViewSource))
          .contains("allOptionsFor = nil Task { await send(pending) }")
          && squashed(withoutComments(askDetailSource))
              .contains("showAllOptions = false send(pending)"))

check("the written-out answer keeps its own explicit send",
      asksViewSource.contains("optionIdx: nil, text: text")
          && askDetailSource.contains("optionIdx: nil, text: ownAnswer"))

// The Lock Screen action is a documented exception, not an oversight: it cannot
// shift under a finger and Face ID already gates it. Guard the decision so it
// stays a decision.
check("the Lock Screen path is the only send that skips the dialog",
      squashed(withoutComments(sourceFile(
          "OffiCraft/Notifications/NotificationManager.swift"
      ))).components(separatedBy: "api.answer(").count == 2)
check("the Lock Screen exception stays documented",
      sourceFile("OffiCraft/Notifications/NotificationManager.swift")
          .contains("Deliberately NOT behind the in-app confirmation dialog"))

// The staged index is resolved by a pure function, so the out-of-range guard is
// testable rather than a promise in a view.
check("an option index past the end falls back instead of trapping",
      AnswerConfirmationCopy.optionText(options: ["a", "b"], optionIdx: 5) == ""
          && AnswerConfirmationCopy.optionText(options: nil, optionIdx: 0) == ""
          && AnswerConfirmationCopy.optionText(options: ["a", "b"], optionIdx: 1) == "b")

// The preview limit itself, not just "some limit": every earlier version of
// these checks passed with the limit set anywhere from 12 upwards.
check("the preview limit keeps 70 characters whole and trims 71",
      AnswerConfirmationCopy.optionPreviewLimit == 70
          && AnswerConfirmationCopy.preview(of: String(repeating: "字", count: 70))
              == String(repeating: "字", count: 70)
          && AnswerConfirmationCopy.preview(of: String(repeating: "字", count: 71))
              == String(repeating: "字", count: 70) + "…")

// MARK: - Summary

print("\n\(checks - failures)/\(checks) checks passed")
if failures > 0 {
    print("\(failures) FAILED")
    exit(1)
}
