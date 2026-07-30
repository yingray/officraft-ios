import SwiftUI
import UIKit
import QuickLook

struct MessageMarkdownPreviewPayload: Identifiable {
    let id: String
    let title: String
    let source: String
    let author: String
    let timestamp: Date
    /// The transcript renders the owner's own messages as plain text — he types
    /// short replies, not documents, and a stray `#` or `|` is a character he
    /// meant. The viewer has to agree with the bubble it was opened from, or
    /// the same message says two different things.
    let rendersMarkdown: Bool
}

/// What the app is currently previewing. One enum so chat, reply cards and task
/// artifacts all route through the same presenter.
enum PreviewTarget: Identifiable {
    /// Image lightbox, with the sibling images so left/right swipes work.
    case image(attachments: [Attachment], index: Int)
    case markdownText(MessageMarkdownPreviewPayload)
    case markdown(Attachment)
    /// Anything else — handed to Quick Look.
    case file(Attachment)

    var id: String {
        switch self {
        case .image(let attachments, let index):
            return "image-\(attachments[safe: index]?.id ?? "0")"
        case .markdownText(let payload): return "message-md-\(payload.id)"
        case .markdown(let attachment): return "md-\(attachment.id)"
        case .file(let attachment): return "file-\(attachment.id)"
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Routes a `PreviewTarget` to the right presentation.
///
/// Deliberately only TWO presentation modifiers: one full-screen cover for the
/// lightbox/message viewer and one sheet that branches between attachment
/// markdown and Quick Look.
/// Stacking a third sheet on the same view is what made these previews
/// unreliable — SwiftUI is fussy about several sheet-class modifiers competing
/// on one node, especially alongside a photo picker or a file importer.
struct AttachmentPreviewPresenter: ViewModifier {
    @Binding var target: PreviewTarget?
    /// Author + timestamp shown in the preview chrome.
    var author: String = ""
    var timestamp: Date?
    var taskNo: String?

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: bindingForFullScreen) { payload in
                switch payload {
                case .image(let image):
                    ImageLightboxView(
                        attachments: image.attachments,
                        startIndex: image.index,
                        author: author,
                        timestamp: timestamp
                    )
                case .markdownText(let message):
                    MessageMarkdownPreviewView(payload: message)
                }
            }
            .sheet(item: bindingForSheet) { payload in
                switch payload.kind {
                case .markdown:
                    MarkdownPreviewView(
                        attachment: payload.attachment,
                        author: author,
                        timestamp: timestamp,
                        taskNo: taskNo
                    )
                case .file:
                    QuickLookView(attachment: payload.attachment)
                }
            }
    }

    private struct ImagePayload: Identifiable {
        let attachments: [Attachment]
        let index: Int
        var id: String { attachments[safe: index]?.id ?? "0" }
    }

    private enum FullScreenPayload: Identifiable {
        case image(ImagePayload)
        case markdownText(MessageMarkdownPreviewPayload)

        var id: String {
            switch self {
            case .image(let image): return "image-\(image.id)"
            case .markdownText(let message): return "message-md-\(message.id)"
            }
        }
    }

    private struct SheetPayload: Identifiable {
        enum Kind { case markdown, file }
        let attachment: Attachment
        let kind: Kind
        var id: String { "\(kind)-\(attachment.id)" }
    }

    private var bindingForFullScreen: Binding<FullScreenPayload?> {
        Binding(
            get: {
                if case .image(let attachments, let index) = target {
                    return .image(
                        ImagePayload(attachments: attachments, index: index)
                    )
                }
                if case .markdownText(let payload) = target {
                    return .markdownText(payload)
                }
                return nil
            },
            set: { if $0 == nil { target = nil } }
        )
    }

    private var bindingForSheet: Binding<SheetPayload?> {
        Binding(
            get: {
                switch target {
                case .markdown(let attachment):
                    return SheetPayload(attachment: attachment, kind: .markdown)
                case .file(let attachment):
                    return SheetPayload(attachment: attachment, kind: .file)
                default:
                    return nil
                }
            },
            set: { if $0 == nil { target = nil } }
        )
    }
}

extension View {
    func attachmentPreview(_ target: Binding<PreviewTarget?>,
                           author: String = "",
                           timestamp: Date? = nil,
                           taskNo: String? = nil) -> some View {
        modifier(AttachmentPreviewPresenter(target: target,
                                            author: author,
                                            timestamp: timestamp,
                                            taskNo: taskNo))
    }
}

/// Maps an attachment to the right preview target.
func previewTarget(for attachment: Attachment, in siblings: [Attachment]) -> PreviewTarget {
    if attachment.isImage {
        let images = siblings.filter(\.isImage)
        let index = images.firstIndex(of: attachment) ?? 0
        return .image(attachments: images, index: index)
    }
    if attachment.isMarkdown { return .markdown(attachment) }
    return .file(attachment)
}

// MARK: - Image lightbox

/// Full-screen image viewer: pinch to zoom, swipe down to dismiss, swipe
/// sideways to change frame.
struct ImageLightboxView: View {
    let attachments: [Attachment]
    let startIndex: Int
    var author: String = ""
    var timestamp: Date?

    @Environment(\.dismiss) private var dismiss
    @Environment(StudioStore.self) private var store

    @State private var index: Int = 0
    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragToDismiss: CGFloat = 0
    @State private var loaded: [String: UIImage] = [:]

    private var current: Attachment? { attachments[safe: index] }

    var body: some View {
        ZStack {
            Color.black
                .opacity(1 - min(0.6, abs(dragToDismiss) / 500))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                chrome
                Spacer(minLength: 0)
                imageArea
                Spacer(minLength: 0)
                footer
            }
        }
        .offset(y: dragToDismiss)
        .statusBarHidden()
        .onAppear { index = startIndex }
        .task(id: index) { await loadCurrent() }
    }

    private var chrome: some View {
        HStack {
            circleButton(.close) { dismiss() }
            Spacer()
            VStack(spacing: 1) {
                Text(current?.filename ?? "")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.ocCaptionSmall)
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            circleButton(.download) { share() }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var subtitle: String {
        var parts: [String] = []
        if attachments.count > 1 { parts.append("\(index + 1) / \(attachments.count)") }
        if !author.isEmpty { parts.append(author) }
        if let timestamp { parts.append(OCFormat.time(timestamp)) }
        return parts.joined(separator: " · ")
    }

    private var imageArea: some View {
        Group {
            if let current, let image = loaded[current.id] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                VStack(spacing: 10) {
                    HatchPattern(spacing: 9)
                        .aspectRatio(4.0 / 3.0, contentMode: .fit)
                        .overlay(
                            Text("\(current?.filename ?? "圖片附件")")
                                .font(.ocMono(12))
                                .foregroundStyle(OC.labelTertiary)
                                .multilineTextAlignment(.center)
                        )
                }
                .padding(.horizontal, 8)
            }
        }
        .scaleEffect(zoom)
        .offset(offset)
        .gesture(zoomGesture)
        .simultaneousGesture(panGesture)
        .highPriorityGesture(pageGesture)
        .onTapGesture(count: 2) {
            withAnimation(.snappy) {
                zoom = zoom > 1 ? 1 : 2.5
                committedZoom = zoom
                offset = .zero
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if attachments.count > 1 {
                HStack(spacing: 8) {
                    ForEach(Array(attachments.enumerated()), id: \.element.id) { position, attachment in
                        Button {
                            withAnimation(.snappy) { select(position) }
                        } label: {
                            Group {
                                if let image = loaded[attachment.id] {
                                    Image(uiImage: image).resizable().scaledToFill()
                                } else {
                                    HatchPattern(spacing: 6)
                                }
                            }
                            .frame(width: 56, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(
                                        position == index ? OC.accent : .white.opacity(0.14),
                                        lineWidth: position == index ? 2 : 1
                                    )
                            )
                            .opacity(position == index ? 1 : 0.6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Text("雙指縮放 · 下滑關閉")
                    .font(.ocFootnote)
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Button("在對話中顯示") { dismiss() }
                    .font(.ocFootnote)
                    .foregroundStyle(OC.accent)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    private func circleButton(_ icon: OCIcon, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Icon(icon, size: 15)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(.white.opacity(0.12)))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Gestures

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom = max(1, min(5, committedZoom * value.magnification))
            }
            .onEnded { _ in
                committedZoom = zoom
                if zoom <= 1 {
                    withAnimation(.snappy) { offset = .zero }
                }
            }
    }

    /// Panning only applies while zoomed in; otherwise a vertical drag is the
    /// dismiss gesture.
    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if zoom > 1 {
                    offset = value.translation
                } else if value.translation.height > 0 {
                    dragToDismiss = value.translation.height
                }
            }
            .onEnded { value in
                if zoom <= 1 {
                    if value.translation.height > 120 {
                        dismiss()
                    } else {
                        withAnimation(.snappy) { dragToDismiss = 0 }
                    }
                }
            }
    }

    /// Horizontal swipe changes frame, but only at 1× so it does not fight
    /// panning a zoomed image.
    private var pageGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard zoom <= 1, attachments.count > 1 else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                withAnimation(.snappy) {
                    select(value.translation.width < 0 ? index + 1 : index - 1)
                }
            }
    }

    private func select(_ newIndex: Int) {
        guard attachments.indices.contains(newIndex) else { return }
        index = newIndex
        zoom = 1
        committedZoom = 1
        offset = .zero
    }

    private func loadCurrent() async {
        guard let current, loaded[current.id] == nil else { return }
        if let data = await store.imageData(for: current), let image = UIImage(data: data) {
            loaded[current.id] = image
        }
    }

    private func share() {
        guard let current, let image = loaded[current.id] else { return }
        ShareSheet.present(items: [image])
    }
}

// MARK: - Message markdown fullscreen

struct MessageMarkdownPreviewView: View {
    let payload: MessageMarkdownPreviewPayload

    @Environment(\.dismiss) private var dismiss
    @State private var didCopy = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                ScrollView {
                    fullText
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                        .padding(.bottom, 28)
                }
                footer
            }
            .background(OC.bg)
            .navigationBarHidden(true)
        }
    }

    /// Markdown for the messages the transcript renders as markdown, plain text
    /// for the ones it does not — same rule either side of the tap.
    @ViewBuilder
    private var fullText: some View {
        if payload.rendersMarkdown {
            MarkdownView(payload.source, scale: .document)
        } else {
            Text(payload.source)
                .font(.ocCallout)
                .foregroundStyle(OC.label)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Icon(.fileText, size: 17)
                    .foregroundStyle(OC.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(payload.title)
                        .font(.ocCalloutEmphasised)
                        .foregroundStyle(OC.label)
                        .lineLimit(1)
                    Text("\(payload.author) · \(OCFormat.time(payload.timestamp))")
                        .font(.ocCaption)
                        .foregroundStyle(OC.labelTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                // The only way out of this cover — no drag-to-dismiss, no nav
                // bar — so the tap target is built the way the rest of the app
                // builds one: inside the label, with .plain.
                Button { dismiss() } label: {
                    Text("完成")
                        .font(.ocCallout)
                        .foregroundStyle(OC.accent)
                        .frame(minWidth: OCMetrics.minTapTarget,
                               minHeight: OCMetrics.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("關閉訊息全文")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            Hairline()
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 10) {
                Text(didCopy ? "全文已複製" : payload.rendersMarkdown
                     ? "Markdown 完整內容" : "訊息完整內容")
                    .font(.ocFootnote)
                    .foregroundStyle(OC.labelTertiary)
                Spacer(minLength: 6)
                Button {
                    UIPasteboard.general.string = payload.source
                    copy()
                } label: {
                    Text(didCopy ? "已複製" : "複製全文")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(OC.accent)
                        .padding(.horizontal, 14)
                        .frame(minHeight: OCMetrics.minTapTarget)
                        .background(Capsule().fill(OC.accentFill))
                }
                .buttonStyle(.plain)
                // The label stays the action; "已複製" is a state, and a
                // VoiceOver user who lands here later still needs to be told
                // what the button does.
                .accessibilityLabel("複製訊息全文")
                .accessibilityValue(didCopy ? "已複製" : "")

                Button {
                    ShareSheet.present(items: [payload.source])
                } label: {
                    Text("分享")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(OC.labelBody)
                        .padding(.horizontal, 14)
                        .frame(minHeight: OCMetrics.minTapTarget)
                        .background(Capsule().fill(OC.surface))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("分享訊息全文")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .background(OC.bg)
    }

    /// Confirmation, not a mode: it goes back to the affordance so a second copy
    /// still looks like a button that does something.
    private func copy() {
        withAnimation(.snappy(duration: 0.18)) { didCopy = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.snappy(duration: 0.18)) { didCopy = false }
        }
    }
}

// MARK: - Markdown sheet

/// Full-text markdown preview.
///
/// Rendered only — there is no source toggle. The raw markdown is what the
/// agent wrote, not what the reader came for, and the share and download
/// buttons already hand over the source for anyone who does want it.
struct MarkdownPreviewView: View {
    let attachment: Attachment
    var author: String = ""
    var timestamp: Date?
    var taskNo: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(StudioStore.self) private var store

    @State private var source: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                content
                footer
            }
            .background(OC.bg)
            .navigationBarHidden(true)
        }
        .presentationDragIndicator(.visible)
        .task {
            source = await store.text(for: attachment)
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Icon(.fileText, size: 17).foregroundStyle(OC.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(attachment.filename)
                        .font(.ocCalloutEmphasised)
                        .foregroundStyle(OC.label)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.ocCaption)
                        .foregroundStyle(OC.labelTertiary)
                }
                Spacer(minLength: 8)
                Button("完成") { dismiss() }
                    .font(.ocCallout)
                    .foregroundStyle(OC.accent)
            }
            .padding(.horizontal, 18)
            // Clear of the sheet's drag indicator, which sits at the very top
            // and otherwise crowds the filename.
            .padding(.top, 20)
            .padding(.bottom, 12)
            Hairline()
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if !author.isEmpty { parts.append(author) }
        if let source { parts.append(OCFormat.fileSize(source.utf8.count)) }
        if let timestamp { parts.append(OCFormat.time(timestamp)) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            Group {
                if let source {
                    MarkdownView(source, scale: .document)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 10) {
                Text(footerLabel)
                    .font(.ocFootnote)
                    .foregroundStyle(OC.labelTertiary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Button {
                    if let source { ShareSheet.present(items: [source]) }
                } label: {
                    Text("分享")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(OC.labelBody)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(OC.surface))
                }
                .buttonStyle(.plain)

                Button {
                    if let source { saveToFiles(source) }
                } label: {
                    Text("下載")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(OC.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(OC.accentFill))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
    }

    private var footerLabel: String {
        var parts: [String] = []
        if !author.isEmpty { parts.append("來自 \(author)") }
        if let taskNo { parts.append("#\(taskNo)") }
        return parts.joined(separator: " · ")
    }

    private func saveToFiles(_ text: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(attachment.filename)
        try? text.write(to: url, atomically: true, encoding: .utf8)
        ShareSheet.present(items: [url])
    }
}

// MARK: - Quick Look

/// Everything that is neither an image nor markdown. Quick Look needs a file
/// on disk, so the bytes are fetched to a temp file first.
struct QuickLookView: View {
    let attachment: Attachment
    @Environment(StudioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var localURL: URL?
    @State private var failed = false

    var body: some View {
        Group {
            if let localURL {
                QuickLookRepresentable(url: localURL)
                    .ignoresSafeArea()
            } else if failed {
                VStack(spacing: 14) {
                    EmptyStateView(icon: .fileText,
                                   title: "打不開這個附件",
                                   message: "檔案下載失敗，稍後再試一次。")
                    Button("關閉") { dismiss() }
                        .font(.ocCallout)
                        .foregroundStyle(OC.accent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(OC.bg)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(OC.bg)
            }
        }
        .task {
            localURL = await store.fileURL(for: attachment)
            failed = localURL == nil
        }
    }
}

private struct QuickLookRepresentable: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        private let url: NSURL

        init(url: URL) { self.url = url as NSURL }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController,
                               previewItemAt index: Int) -> QLPreviewItem { url }
    }
}

// MARK: - Share sheet

enum ShareSheet {
    /// Presents the system share sheet from the active scene.
    @MainActor
    static func present(items: [Any]) {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.keyWindow?.rootViewController else { return }

        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // iPad requires an anchor or the popover asserts.
        if let popover = controller.popoverPresentationController {
            popover.sourceView = root.view
            popover.sourceRect = CGRect(x: root.view.bounds.midX,
                                        y: root.view.bounds.maxY - 40,
                                        width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        root.presented(topMost: true).present(controller, animated: true)
    }
}

private extension UIViewController {
    /// Walks to the top-most presented controller so the share sheet is not
    /// swallowed by an already-open sheet.
    func presented(topMost: Bool) -> UIViewController {
        var controller: UIViewController = self
        while let next = controller.presentedViewController { controller = next }
        return controller
    }
}
