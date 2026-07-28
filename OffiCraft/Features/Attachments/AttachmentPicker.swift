import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// A file the owner picked but has not sent yet.
struct PendingAttachment: Identifiable, Hashable {
    let id = UUID()
    var filename: String
    var mime: String
    var data: Data

    var isImage: Bool { mime.hasPrefix("image/") }

    var sizeLabel: String { OCFormat.fileSize(data.count) }
}

/// The staged attachments above the composer, each removable before sending.
struct AttachmentTray: View {
    @Binding var attachments: [PendingAttachment]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    HStack(spacing: 8) {
                        if attachment.isImage, let image = UIImage(data: attachment.data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 34, height: 34)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        } else {
                            Icon(.fileText, size: 15)
                                .foregroundStyle(OC.accent)
                                .frame(width: 34, height: 34)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(OC.surface2)
                                )
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(attachment.filename)
                                .font(.ocCaption)
                                .foregroundStyle(OC.labelBody)
                                .lineLimit(1)
                            Text(attachment.sizeLabel)
                                .font(.ocCaptionSmall)
                                .foregroundStyle(OC.labelQuaternary)
                        }

                        Button {
                            attachments.removeAll { $0.id == attachment.id }
                        } label: {
                            Icon(.close, size: 11)
                                .foregroundStyle(OC.labelTertiary)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("移除 \(attachment.filename)")
                    }
                    .padding(.leading, 6)
                    .padding(.trailing, 2)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(OC.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(OC.hairline, lineWidth: 1)
                            )
                    )
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 50)
    }
}

/// Wires the composer's `+` to the photo library and the file browser.
///
/// Files are read into memory because the wire takes them base64-inline
/// (`POST /api/chat` → `attachments[].data_b64`), so there is no upload session
/// to manage — the cap below is what keeps that honest.
struct AttachmentPickerModifier: ViewModifier {
    @Binding var attachments: [PendingAttachment]
    @Binding var isPresentingPhotos: Bool
    @Binding var isPresentingFiles: Bool
    @Binding var errorMessage: String?

    /// Inline base64 means the whole file rides in one JSON body. 12 MB is a
    /// generous ceiling for a screenshot or a report and well short of trouble.
    private static let sizeLimit = 12 * 1024 * 1024

    @State private var photoSelection: [PhotosPickerItem] = []

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $isPresentingPhotos,
                          selection: $photoSelection,
                          maxSelectionCount: 5,
                          matching: .any(of: [.images, .screenshots]))
            .onChange(of: photoSelection) {
                let picked = photoSelection
                photoSelection = []
                Task { await load(picked) }
            }
            .fileImporter(isPresented: $isPresentingFiles,
                          allowedContentTypes: [.item],
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): load(urls)
                case .failure(let error): errorMessage = error.localizedDescription
                }
            }
    }

    private func load(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            guard data.count <= Self.sizeLimit else {
                errorMessage = "圖片超過 \(OCFormat.fileSize(Self.sizeLimit))，換一張小一點的。"
                continue
            }
            let type = item.supportedContentTypes.first
            let ext = type?.preferredFilenameExtension ?? "jpg"
            attachments.append(
                PendingAttachment(
                    filename: "image-\(attachments.count + 1).\(ext)",
                    mime: type?.preferredMIMEType ?? "image/jpeg",
                    data: data
                )
            )
        }
    }

    private func load(_ urls: [URL]) {
        for url in urls {
            // Files outside the app container need a security scope held open
            // for the duration of the read.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            guard let data = try? Data(contentsOf: url) else {
                errorMessage = "讀不到 \(url.lastPathComponent)。"
                continue
            }
            guard data.count <= Self.sizeLimit else {
                errorMessage = "\(url.lastPathComponent) 超過 \(OCFormat.fileSize(Self.sizeLimit))。"
                continue
            }
            let type = UTType(filenameExtension: url.pathExtension)
            attachments.append(
                PendingAttachment(
                    filename: url.lastPathComponent,
                    mime: type?.preferredMIMEType ?? "application/octet-stream",
                    data: data
                )
            )
        }
    }
}

extension View {
    func attachmentPicker(attachments: Binding<[PendingAttachment]>,
                          isPresentingPhotos: Binding<Bool>,
                          isPresentingFiles: Binding<Bool>,
                          errorMessage: Binding<String?>) -> some View {
        modifier(AttachmentPickerModifier(
            attachments: attachments,
            isPresentingPhotos: isPresentingPhotos,
            isPresentingFiles: isPresentingFiles,
            errorMessage: errorMessage
        ))
    }
}
