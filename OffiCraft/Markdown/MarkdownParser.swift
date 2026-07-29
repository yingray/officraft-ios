import Foundation

/// Block-level markdown AST.
///
/// `AttributedString(markdown:)` only handles inline syntax, but the design doc
/// needs real blocks — headings, alerts, fenced code with a language chrome,
/// tables that scroll horizontally, task lists with checkboxes. So blocks are
/// parsed here and inline runs are handed to `AttributedString` per leaf.
enum MarkdownBlock: Identifiable, Hashable {
    case heading(level: Int, text: String)
    case paragraph(String)
    /// GitHub-style callout: `> [!NOTE]` … Rendered with a left rule.
    case alert(kind: AlertKind, lines: [String])
    case quote([String])
    case bulletList([ListItem])
    case orderedList([ListItem])
    case taskList([TaskItem])
    case code(language: String?, source: String)
    case table(header: [String], rows: [[String]], alignments: [ColumnAlignment])
    case divider

    var id: Int { hashValue }

    struct ListItem: Hashable {
        let text: String
        /// Nesting depth, 0-based.
        var depth: Int = 0
    }

    struct TaskItem: Hashable {
        let text: String
        let isDone: Bool
        var depth: Int = 0
    }

    /// Column alignment from the delimiter row: `:---` / `:---:` / `---:`.
    enum ColumnAlignment: Hashable {
        case leading, center, trailing
    }

    enum AlertKind: String, Hashable {
        case note = "NOTE"
        case tip = "TIP"
        case important = "IMPORTANT"
        case warning = "WARNING"
        case caution = "CAUTION"
    }
}

enum MarkdownParser {

    static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Blank
            if trimmed.isEmpty {
                index += 1
                continue
            }

            // Fenced code — the fence may carry a language hint.
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let fence = String(trimmed.prefix(3))
                let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                var body: [String] = []
                index += 1
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    if candidate.hasPrefix(fence) { index += 1; break }
                    body.append(lines[index])
                    index += 1
                }
                blocks.append(.code(
                    language: language.isEmpty ? nil : language.lowercased(),
                    source: body.joined(separator: "\n")
                ))
                continue
            }

            // Thematic break
            if isDivider(trimmed) {
                blocks.append(.divider)
                index += 1
                continue
            }

            // ATX heading
            if trimmed.hasPrefix("#") {
                let hashes = trimmed.prefix { $0 == "#" }.count
                if hashes <= 6, trimmed.dropFirst(hashes).hasPrefix(" ") {
                    let text = trimmed.dropFirst(hashes).trimmingCharacters(in: .whitespaces)
                    blocks.append(.heading(level: hashes, text: text))
                    index += 1
                    continue
                }
            }

            // Table — a header row followed by a delimiter row.
            if isTableStart(lines, index) {
                let header = splitRow(trimmed)
                let alignments = columnAlignments(lines[index + 1])
                var rows: [[String]] = []
                index += 2
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.contains("|"), !candidate.isEmpty else { break }
                    // A bullet or heading that happens to contain a pipe is the
                    // next block, not another row.
                    guard !startsBlock(candidate) else { break }
                    rows.append(splitRow(candidate))
                    index += 1
                }
                blocks.append(.table(header: header, rows: rows, alignments: alignments))
                continue
            }

            // Blockquote / alert
            if trimmed.hasPrefix(">") {
                var quoted: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">") else { break }
                    var content = String(candidate.dropFirst())
                    if content.hasPrefix(" ") { content.removeFirst() }
                    quoted.append(content)
                    index += 1
                }
                if let first = quoted.first,
                   let kind = alertKind(from: first) {
                    let body = Array(quoted.dropFirst()).drop { $0.trimmingCharacters(in: .whitespaces).isEmpty }
                    blocks.append(.alert(kind: kind, lines: Array(body)))
                } else {
                    blocks.append(.quote(quoted))
                }
                continue
            }

            // Task list — checked before the plain bullet list, since the
            // marker is a bullet with a `[ ]` prefix.
            if taskItem(from: trimmed) != nil {
                var items: [MarkdownBlock.TaskItem] = []
                while index < lines.count {
                    let raw = lines[index]
                    let candidate = raw.trimmingCharacters(in: .whitespaces)
                    guard let item = taskItem(from: candidate) else { break }
                    items.append(.init(text: item.text, isDone: item.isDone, depth: indentDepth(raw)))
                    index += 1
                }
                blocks.append(.taskList(items))
                continue
            }

            // Bullet list
            if isBullet(trimmed) {
                var items: [MarkdownBlock.ListItem] = []
                while index < lines.count {
                    let raw = lines[index]
                    let candidate = raw.trimmingCharacters(in: .whitespaces)
                    guard isBullet(candidate), taskItem(from: candidate) == nil else { break }
                    let text = candidate.dropFirst(1).trimmingCharacters(in: .whitespaces)
                    items.append(.init(text: text, depth: indentDepth(raw)))
                    index += 1
                }
                blocks.append(.bulletList(items))
                continue
            }

            // Ordered list
            if orderedMarkerLength(trimmed) > 0 {
                var items: [MarkdownBlock.ListItem] = []
                while index < lines.count {
                    let raw = lines[index]
                    let candidate = raw.trimmingCharacters(in: .whitespaces)
                    let markerLength = orderedMarkerLength(candidate)
                    guard markerLength > 0 else { break }
                    let text = String(candidate.dropFirst(markerLength))
                        .trimmingCharacters(in: .whitespaces)
                    items.append(.init(text: text, depth: indentDepth(raw)))
                    index += 1
                }
                blocks.append(.orderedList(items))
                continue
            }

            // Paragraph — runs until a blank line or a block starter.
            var paragraph: [String] = []
            while index < lines.count {
                let raw = lines[index]
                let candidate = raw.trimmingCharacters(in: .whitespaces)
                if candidate.isEmpty || startsBlock(candidate) { break }
                // A table needs two lines to recognise, which `startsBlock`
                // cannot do from one — check it separately or the table gets
                // eaten by the paragraph.
                if isTableStart(lines, index) { break }
                paragraph.append(candidate)
                index += 1
            }
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
            }
        }

        return blocks
    }

    // MARK: - Line classification

    private static func startsBlock(_ line: String) -> Bool {
        line.hasPrefix("#") || line.hasPrefix(">") || line.hasPrefix("```")
            || line.hasPrefix("~~~") || isBullet(line) || orderedMarkerLength(line) > 0
            || isDivider(line)
    }

    private static func isBullet(_ line: String) -> Bool {
        guard let first = line.first, first == "-" || first == "*" || first == "+" else { return false }
        return line.dropFirst().hasPrefix(" ")
    }

    /// Length of an `1. ` / `12) ` marker, or 0 when the line is not ordered.
    private static func orderedMarkerLength(_ line: String) -> Int {
        var digits = 0
        for character in line {
            if character.isNumber { digits += 1 } else { break }
        }
        guard digits > 0, digits < line.count else { return 0 }
        let separatorIndex = line.index(line.startIndex, offsetBy: digits)
        let separator = line[separatorIndex]
        guard separator == "." || separator == ")" else { return 0 }
        let afterIndex = line.index(after: separatorIndex)
        guard afterIndex < line.endIndex, line[afterIndex] == " " else { return 0 }
        return digits + 2
    }

    private static func isDivider(_ line: String) -> Bool {
        let stripped = line.replacingOccurrences(of: " ", with: "")
        guard stripped.count >= 3 else { return false }
        return stripped.allSatisfy { $0 == "-" } || stripped.allSatisfy { $0 == "*" }
            || stripped.allSatisfy { $0 == "_" }
    }

    private static func taskItem(from line: String) -> (text: String, isDone: Bool)? {
        guard isBullet(line) else { return nil }
        let afterBullet = line.dropFirst(1).trimmingCharacters(in: .whitespaces)
        guard afterBullet.hasPrefix("[") , afterBullet.count > 3 else { return nil }
        let markerIndex = afterBullet.index(afterBullet.startIndex, offsetBy: 1)
        let closingIndex = afterBullet.index(afterBullet.startIndex, offsetBy: 2)
        guard afterBullet[closingIndex] == "]" else { return nil }
        let marker = afterBullet[markerIndex]
        let isDone = marker == "x" || marker == "X"
        guard isDone || marker == " " else { return nil }
        let text = afterBullet
            .dropFirst(3)
            .trimmingCharacters(in: .whitespaces)
        return (text, isDone)
    }

    /// Two spaces (or one tab) per nesting level, the common convention.
    private static func indentDepth(_ raw: String) -> Int {
        var spaces = 0
        for character in raw {
            if character == " " { spaces += 1 }
            else if character == "\t" { spaces += 4 }
            else { break }
        }
        return min(spaces / 2, 3)
    }

    private static func alertKind(from line: String) -> MarkdownBlock.AlertKind? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[!"), let close = trimmed.firstIndex(of: "]") else { return nil }
        let raw = trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<close]
        return MarkdownBlock.AlertKind(rawValue: raw.uppercased())
    }

    /// A table starts where a pipe-bearing line is followed by a delimiter row
    /// with the same number of cells. GFM requires the counts to match, and
    /// without that check a prose line containing a pipe followed by anything
    /// dash-shaped gets torn out of its paragraph and promoted to a header.
    private static func isTableStart(_ lines: [String], _ index: Int) -> Bool {
        guard index + 1 < lines.count else { return false }
        let header = lines[index]
        guard header.contains("|"), isTableDelimiter(lines[index + 1]) else { return false }
        return splitRow(header).count == splitRow(lines[index + 1]).count
    }

    /// Reads `:---` / `:---:` / `---:` out of the delimiter row.
    private static func columnAlignments(_ line: String) -> [MarkdownBlock.ColumnAlignment] {
        splitRow(line).map { spec in
            let leading = spec.hasPrefix(":")
            let trailing = spec.hasSuffix(":")
            switch (leading, trailing) {
            case (true, true): return .center
            case (false, true): return .trailing
            default: return .leading
            }
        }
    }

    private static func isTableDelimiter(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-"), trimmed.contains("|") else { return false }
        return trimmed.allSatisfy { $0 == "|" || $0 == "-" || $0 == ":" || $0 == " " }
    }

    private static func splitRow(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

// MARK: - Inline

extension MarkdownParser {
    /// Inline runs (bold / italic / code / links) via `AttributedString`.
    /// Falls back to plain text when the source has syntax Foundation rejects.
    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        if let attributed = try? AttributedString(markdown: text, options: options) {
            return attributed
        }
        return AttributedString(text)
    }
}
