import SwiftUI
import UIKit

/// Renders parsed markdown.
///
/// Design-doc interaction rule: "程式碼／表格是唯一允許橫向捲動的區塊" — every
/// other block wraps, and only code and tables get their own horizontal
/// scroller.
struct MarkdownView: View {
    let blocks: [MarkdownBlock]
    /// Slightly tighter type inside chat bubbles than in a full-screen sheet.
    var scale: Scale = .message
    var onOpenLink: ((URL) -> Void)?

    enum Scale {
        /// Chat bubbles, reply-card bodies.
        case message
        /// Full-screen markdown preview sheet.
        case document

        var body: CGFloat { self == .document ? 15 : 14.5 }
        var heading1: CGFloat { self == .document ? 23 : 18 }
        var heading2: CGFloat { self == .document ? 17 : 16 }
        var heading3: CGFloat { self == .document ? 15.5 : 15 }
        var spacing: CGFloat { self == .document ? 12 : 10 }
        var code: CGFloat { 12.5 }
    }

    init(_ source: String, scale: Scale = .message, onOpenLink: ((URL) -> Void)? = nil) {
        self.blocks = MarkdownParser.parse(source)
        self.scale = scale
        self.onOpenLink = onOpenLink
    }

    init(blocks: [MarkdownBlock], scale: Scale = .message) {
        self.blocks = blocks
        self.scale = scale
    }

    var body: some View {
        VStack(alignment: .leading, spacing: scale.spacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(MarkdownParser.inline(text))
                .font(.system(size: headingSize(level), weight: .bold))
                .foregroundStyle(OC.label)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

        case .paragraph(let text):
            Text(MarkdownParser.inline(text))
                .font(.system(size: scale.body))
                .foregroundStyle(OC.labelSecondary)
                .lineSpacing(scale.body * 0.55)
                .fixedSize(horizontal: false, vertical: true)
                .tint(OC.accent)

        case .alert(let kind, let lines):
            AlertBlock(kind: kind, lines: lines, scale: scale)

        case .quote(let lines):
            HStack(alignment: .top, spacing: 11) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(OC.labelQuaternary)
                    .frame(width: 3)
                Text(MarkdownParser.inline(lines.joined(separator: "\n")))
                    .font(.system(size: scale.body))
                    .foregroundStyle(OC.labelTertiary)
                    .lineSpacing(scale.body * 0.5)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text("▪")
                            .font(.system(size: scale.body))
                            .foregroundStyle(OC.accent)
                        Text(MarkdownParser.inline(item.text))
                            .font(.system(size: scale.body))
                            .foregroundStyle(OC.labelSecondary)
                            .lineSpacing(scale.body * 0.45)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(item.depth) * 16)
                }
            }

        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text("\(index + 1).")
                            .font(.system(size: scale.body, weight: .semibold))
                            .foregroundStyle(OC.accent)
                            .monospacedDigit()
                        Text(MarkdownParser.inline(item.text))
                            .font(.system(size: scale.body))
                            .foregroundStyle(OC.labelSecondary)
                            .lineSpacing(scale.body * 0.45)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(item.depth) * 16)
                }
            }

        case .taskList(let items):
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .center, spacing: 9) {
                        CheckBox(isDone: item.isDone)
                        Text(MarkdownParser.inline(item.text))
                            .font(.system(size: scale.body))
                            .foregroundStyle(item.isDone ? OC.labelTertiary : OC.labelBody)
                            .strikethrough(item.isDone, color: OC.labelQuaternary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(item.depth) * 16)
                }
            }

        case .code(let language, let source):
            CodeBlock(language: language, source: source, fontSize: scale.code)

        case .table(let header, let rows, let alignments):
            TableBlock(header: header, rows: rows, alignments: alignments)

        case .divider:
            Hairline()
                .padding(.vertical, 2)
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return scale.heading1
        case 2: return scale.heading2
        default: return scale.heading3
        }
    }
}

// MARK: - Checkbox

private struct CheckBox: View {
    let isDone: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isDone ? OC.accent : .clear)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(isDone ? .clear : OC.labelQuaternary, lineWidth: 1.5)
            if isDone {
                Icon(.check, size: 12)
                    .foregroundStyle(Color(hex: 0x10131A))
            }
        }
        .frame(width: 18, height: 18)
    }
}

// MARK: - Alert

private struct AlertBlock: View {
    let kind: MarkdownBlock.AlertKind
    let lines: [String]
    let scale: MarkdownView.Scale

    private var tint: Color {
        switch kind {
        case .note: return OC.alertNote
        case .tip: return OC.alertTip
        case .important: return OC.alertImportant
        case .warning: return OC.alertWarning
        case .caution: return OC.alertCaution
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(tint).frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(kind.rawValue)
                    .font(.system(size: 12.5, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(tint)
                if !lines.isEmpty {
                    Text(MarkdownParser.inline(lines.joined(separator: "\n")))
                        .font(.system(size: scale.body))
                        .foregroundStyle(OC.labelSecondary)
                        .lineSpacing(scale.body * 0.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
        }
        .background(tint.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Code

/// Fenced code with the language chrome and a copy affordance.
/// One of the two blocks allowed to scroll horizontally.
struct CodeBlock: View {
    let language: String?
    let source: String
    var fontSize: CGFloat = 12.5

    @State private var didCopy = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(language ?? "text")
                    .font(.ocMono(11))
                    .foregroundStyle(OC.labelTertiary)
                Spacer()
                Button {
                    UIPasteboard.general.string = source
                    withAnimation(.snappy) { didCopy = true }
                    Task {
                        try? await Task.sleep(nanoseconds: 1_600_000_000)
                        withAnimation(.snappy) { didCopy = false }
                    }
                } label: {
                    Text(didCopy ? "已複製" : "複製")
                        .font(.ocMono(11))
                        .foregroundStyle(didCopy ? OC.accent : OC.labelTertiary)
                        .frame(minHeight: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(OC.label.opacity(0.03))

            Hairline()

            ScrollView(.horizontal, showsIndicators: false) {
                Text(CodeHighlighter.highlight(source, language: language))
                    .font(.ocMono(fontSize))
                    .lineSpacing(fontSize * 0.7)
                    .textSelection(.enabled)
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(OC.surfaceCode)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(OC.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Table

/// The other horizontally scrollable block.
///
/// Laid out with `Grid`, which is the whole point: it negotiates one width per
/// column across every row. The previous per-row `HStack` sized each row from
/// its own text, so a long cell in the body pushed that row's columns out of
/// register with the header — the reported 跑版.
struct TableBlock: View {
    let header: [String]
    let rows: [[String]]
    var alignments: [MarkdownBlock.ColumnAlignment] = []

    private var columnCount: Int {
        max(header.count, rows.map(\.count).max() ?? 0)
    }

    private func alignment(_ column: Int) -> HorizontalAlignment {
        guard alignments.indices.contains(column) else { return .leading }
        switch alignments[column] {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private func textAlignment(_ column: Int) -> TextAlignment {
        switch alignment(column) {
        case .center: return .center
        case .trailing: return .trailing
        default: return .leading
        }
    }

    private func frameAlignment(_ column: Int) -> Alignment {
        switch alignment(column) {
        case .center: return .center
        case .trailing: return .trailing
        default: return .leading
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(0..<columnCount, id: \.self) { column in
                        cell(header.indices.contains(column) ? header[column] : "",
                             isHeader: true,
                             column: column)
                            .gridColumnAlignment(alignment(column))
                    }
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Hairline()
                        .gridCellUnsizedAxes(.horizontal)
                        .gridCellColumns(columnCount)
                    GridRow {
                        ForEach(0..<columnCount, id: \.self) { column in
                            cell(row.indices.contains(column) ? row[column] : "",
                                 isHeader: false,
                                 column: column)
                        }
                    }
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(OC.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func cell(_ text: String, isHeader: Bool, column: Int) -> some View {
        Text(MarkdownParser.inline(text))
            .font(.system(size: 12.5, weight: isHeader ? .bold : .regular))
            .foregroundStyle(isHeader ? OC.labelSecondary : OC.labelBody)
            .multilineTextAlignment(textAlignment(column))
            // One line per cell, deliberately. The enclosing ScrollView
            // proposes unbounded width, so anything that wraps would be
            // measured for one line and then laid out taller, spilling into
            // the neighbouring rows. A long value widens the table instead and
            // the reader scrolls — which is what the interaction rules allow
            // tables to do.
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            // maxHeight fills the row so the header tint has no vertical gaps:
            // a cell frame constrains width only, and a short label would
            // otherwise sit centred with untinted bands above and below.
            .frame(minWidth: column == 0 ? 96 : 66,
                   maxHeight: .infinity,
                   alignment: frameAlignment(column))
            // The tint has to sit on the cell — GridRow takes no background.
            .background(isHeader ? OC.label.opacity(0.04) : Color.clear)
    }
}
