import SwiftUI

/// Lays subviews left to right, wrapping to a new line when the next one would
/// not fit.
///
/// Attachment thumbnails are fixed-size (104×78 by design), so a plain `HStack`
/// overflows the bubble as soon as there are three of them — and the design
/// rules reserve horizontal scrolling for code and tables, so it cannot scroll
/// out of the problem either. Wrapping is the honest answer.
struct FlowLayout: Layout {
    var spacing: CGFloat = 9
    var lineSpacing: CGFloat = 9

    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let lines = layout(subviews: subviews, maxWidth: maxWidth)

        let width = lines
            .map { line in line.reduce(0) { $0 + $1.size.width } + spacing * CGFloat(max(0, line.count - 1)) }
            .max() ?? 0
        let height = lines
            .map { line in line.map(\.size.height).max() ?? 0 }
            .reduce(0, +)
            + lineSpacing * CGFloat(max(0, lines.count - 1))

        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout ()) {
        let lines = layout(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY

        for line in lines {
            var x = bounds.minX
            let lineHeight = line.map(\.size.height).max() ?? 0
            for item in line {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (lineHeight - item.size.height) / 2),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += lineHeight + lineSpacing
        }
    }

    private struct Item {
        let index: Int
        let size: CGSize
    }

    private func layout(subviews: Subviews, maxWidth: CGFloat) -> [[Item]] {
        var lines: [[Item]] = []
        var line: [Item] = []
        var lineWidth: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = line.isEmpty ? size.width : lineWidth + spacing + size.width
            if !line.isEmpty, needed > maxWidth {
                lines.append(line)
                line = [Item(index: index, size: size)]
                lineWidth = size.width
            } else {
                line.append(Item(index: index, size: size))
                lineWidth = needed
            }
        }
        if !line.isEmpty { lines.append(line) }
        return lines
    }
}
