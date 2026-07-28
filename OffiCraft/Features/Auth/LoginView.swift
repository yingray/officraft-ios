import SwiftUI

/// 連到你的工作室 — the first-run screen.
///
/// The server binds 127.0.0.1 and is not exposed by default, so the app has to
/// be told a host before anything else. The password (key) is exchanged once
/// for a long-lived token; after that it is Face ID.
struct LoginView: View {
    @Environment(AppSession.self) private var session

    @State private var host: String = ""
    @State private var password: String = ""
    @State private var remember: Bool = true
    @State private var revealPassword = false
    @State private var isConnecting = false
    @State private var errorMessage: String?

    @FocusState private var focus: Field?
    private enum Field { case host, password }

    private var parsedHost: ServerHost { ServerHost(raw: host) }
    private var canConnect: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
            && !isConnecting
    }

    var body: some View {
        ZStack {
            OC.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    fields
                    Spacer(minLength: 20)
                    troubleshooting
                }
                .padding(.horizontal, 26)
                .padding(.top, 34)
                .padding(.bottom, 28)
                .frame(minHeight: UIScreen.main.bounds.height - 100, alignment: .top)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            if host.isEmpty, let existing = session.activeHost {
                host = existing.display
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            BrandMark(size: 56)
            VStack(alignment: .leading, spacing: 6) {
                Text("連到你的工作室")
                    .font(.ocDisplay)
                    .foregroundStyle(OC.label)
                Text("Connect to your studio · 輸入控制台網址與 owner 密碼")
                    .font(.ocCallout)
                    .foregroundStyle(OC.labelTertiary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Fields

    private var fields: some View {
        VStack(alignment: .leading, spacing: 16) {
            hostField
            passwordField

            HStack(spacing: 12) {
                Text("記住這台裝置")
                    .font(.ocCallout)
                    .foregroundStyle(OC.label)
                Spacer()
                Toggle("", isOn: $remember)
                    .labelsHidden()
                    .tint(OC.toggleOn)
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)

            if let errorMessage {
                Text(errorMessage)
                    .font(.ocFootnote)
                    .foregroundStyle(OC.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            connectButton

            HStack(spacing: 8) {
                Icon(.faceID, size: 17)
                Text("下次用 \(Biometrics.available.label) 解鎖")
                    .font(.ocSubhead)
            }
            .foregroundStyle(OC.labelSecondary)
            .frame(maxWidth: .infinity)

            Button {
                session.enterDemo()
            } label: {
                Text("先用示範資料看看")
                    .font(.ocFootnote)
                    .foregroundStyle(OC.accent)
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.plain)
        }
    }

    private var hostField: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("HOST 主機網址").ocSectionLabel().padding(.leading, 2)

            HStack(spacing: 9) {
                Icon(.globe, size: 16).foregroundStyle(OC.labelTertiary)
                TextField("officraft.example.com", text: $host)
                    .font(.ocMono(15))
                    .foregroundStyle(OC.labelBody)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .focused($focus, equals: .host)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }

                if !host.isEmpty {
                    Text(parsedHost.scheme.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(OC.labelTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(OC.surface2)
                        )
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(fieldBackground(focused: focus == .host))

            Text("也可以填 127.0.0.1:7755（同一台 Mac）或你的 tunnel／VPN 網址")
                .font(.ocCaption)
                .foregroundStyle(OC.labelQuaternary)
                .lineSpacing(2)
                .padding(.leading, 2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var passwordField: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("密碼 KEY").ocSectionLabel().padding(.leading, 2)

            HStack(spacing: 9) {
                Icon(.lock, size: 16).foregroundStyle(OC.labelTertiary)
                Group {
                    if revealPassword {
                        TextField("owner 密碼", text: $password)
                    } else {
                        SecureField("owner 密碼", text: $password)
                    }
                }
                .font(.system(size: 17))
                .foregroundStyle(OC.labelBody)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.password)
                .focused($focus, equals: .password)
                .submitLabel(.go)
                .onSubmit { connect() }

                Button {
                    revealPassword.toggle()
                } label: {
                    Icon(.eye, size: 16)
                        .foregroundStyle(revealPassword ? OC.accent : OC.labelTertiary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(revealPassword ? "隱藏密碼" : "顯示密碼")
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(fieldBackground(focused: focus == .password))
        }
    }

    private func fieldBackground(focused: Bool) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(OC.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(focused ? OC.accentBorder : OC.hairline, lineWidth: 1)
            )
    }

    private var connectButton: some View {
        Button(action: connect) {
            ZStack {
                if isConnecting {
                    ProgressView().tint(OC.accent)
                } else {
                    Text("連線")
                        .font(.ocBodyLarge.weight(.semibold))
                }
            }
            .foregroundStyle(canConnect ? OC.accent : OC.labelQuaternary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(canConnect ? OC.accentFill : OC.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(canConnect ? OC.accentBorder : OC.hairline, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!canConnect)
    }

    // MARK: Troubleshooting

    private var troubleshooting: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("連不上？")
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(OC.labelSecondary)
            Text("server 預設只綁 127.0.0.1、不對外。要從外面連，先開一條自己的 tunnel（如 cloudflared）或走 VPN。")
                .font(.ocFootnoteSmall)
                .foregroundStyle(OC.labelTertiary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(OC.surface)
        )
    }

    // MARK: Actions

    private func connect() {
        guard canConnect else { return }
        focus = nil
        errorMessage = nil
        isConnecting = true
        Task {
            do {
                try await session.signIn(host: host, password: password, remember: remember)
            } catch {
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
            isConnecting = false
        }
    }
}
