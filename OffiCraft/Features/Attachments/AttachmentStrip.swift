import SwiftUI
import UIKit

/// Tap targets for attachments — image thumbnails and `.md` chips.
///
/// The doc pins the behaviour: a thumbnail opens a full-screen lightbox, an
/// `.md` chip opens the markdown sheet, anything else goes to Quick Look. The
/// same strip is used by chat, reply cards and task artifacts.
struct AttachmentStrip: View {
    let attachments: [Attachment]
    var compact: Bool = false
    var onOpen: (Attachment) -> Void

    private var images: [Attachment] { attachments.filter(\.isImage) }
    private var files: [Attachment] { attachments.filter { !$0.isImage } }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if !images.isEmpty {
                // Wraps rather than overflowing: three 104pt thumbnails do not
                // fit a chat bubble, and tables and code are the only blocks
                // allowed to scroll sideways.
                FlowLayout(spacing: 9, lineSpacing: 9) {
                    ForEach(images) { attachment in
                        Button { onOpen(attachment) } label: {
                            ImageThumbnail(attachment: attachment, compact: compact)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("圖片 \(attachment.filename)")
                    }
                }
            }

            ForEach(files) { attachment in
                Button { onOpen(attachment) } label: {
                    FileChip(attachment: attachment)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Thumbnail

private struct ImageThumbnail: View {
    let attachment: Attachment
    var compact: Bool
    @Environment(StudioStore.self) private var store
    @State private var image: UIImage?

    private var width: CGFloat { compact ? 56 : 104 }
    private var height: CGFloat { compact ? 44 : 78 }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipped()
            } else {
                // Hatched placeholder, matching the doc's image stand-in.
                HatchPattern()
                    .frame(width: width, height: height)
                if !compact {
                    Text(attachment.filename)
                        .font(.ocMono(9.5))
                        .foregroundStyle(OC.labelTertiary)
                        .lineLimit(1)
                        .padding(6)
                } else {
                    Text("IMG")
                        .font(.system(size: 11))
                        .foregroundStyle(OC.labelTertiary)
                        .frame(width: width, height: height)
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 9 : 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 9 : 12, style: .continuous)
                .strokeBorder(OC.hairline, lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            if !compact {
                Icon(.eye, size: 12)
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(.black.opacity(0.5)))
                    .padding(6)
            }
        }
        .task {
            if let data = await store.imageData(for: attachment) {
                image = UIImage(data: data)
            }
        }
    }
}

/// The diagonal hatch used wherever an image has not loaded (or, in the demo
/// studio, does not exist).
struct HatchPattern: View {
    var spacing: CGFloat = 7

    var body: some View {
        Canvas { context, size in
            let base = Path(CGRect(origin: .zero, size: size))
            context.fill(base, with: .color(OC.dyn(light: 0xE9E9EF, dark: 0x1A1D22)))
            var stripes = Path()
            var x = -size.height
            while x < size.width {
                stripes.move(to: CGPoint(x: x, y: size.height))
                stripes.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing * 2
            }
            context.stroke(
                stripes,
                with: .color(OC.dyn(light: 0xDCDCE4, dark: 0x22252B)),
                lineWidth: spacing
            )
        }
    }
}

// MARK: - File chip

private struct FileChip: View {
    let attachment: Attachment

    var body: some View {
        HStack(spacing: 9) {
            Icon(.fileText, size: 16)
                .foregroundStyle(attachment.isMarkdown ? OC.accent : OC.labelTertiary)
            Text(attachment.filename)
                .font(.ocFootnote)
                .foregroundStyle(OC.labelBody)
                .lineLimit(1)
            if attachment.opensInApp {
                Text("預覽")
                    .font(.ocCaption)
                    .foregroundStyle(OC.accent)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(minHeight: OCMetrics.minTapTarget)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(OC.surface2)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            attachment.isMarkdown ? OC.accentBorder.opacity(0.8) : OC.hairline,
                            lineWidth: 1
                        )
                )
        )
        .contentShape(Rectangle())
    }
}
