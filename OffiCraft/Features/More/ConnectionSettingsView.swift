import SwiftUI

/// 設定 · 連線與安全 — change host, test it, rotate the password.
struct ConnectionSettingsView: View {
    @Environment(AppSession.self) private var session

    @State private var isTesting = false
    @State private var showHostSwitcher = false
    @State private var showChangePassword = false
    @State private var showSignOutConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                hostSection
                securitySection
                buildFooter
            }
            .padding(OCMetrics.screenPadding)
            .padding(.bottom, 24)
        }
        .background(OC.bg)
        .navigationTitle("連線與安全")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showHostSwitcher) { HostSwitcherView() }
        .sheet(isPresented: $showChangePassword) { ChangePasswordView() }
        .confirmationDialog("登出這台裝置？", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button("登出", role: .destructive) { session.signOut() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("下次要重新輸入 host 與密碼。其他裝置不受影響。")
        }
        .task { await session.testConnection() }
    }

    // MARK: Host

    private var hostSection: some View {
        GroupedSection(
            header: "主機 HOST",
            footer: "本機、tunnel、VPN 可各存一組，出門在外一鍵切換。"
        ) {
            GroupedRow(title: "網址", trailing: {
                Text(session.activeHost?.display ?? "未設定")
                    .font(.ocMono(14))
                    .foregroundStyle(OC.labelTertiary)
                    .lineLimit(1)
            })

            GroupedRow(title: "連線狀態", trailing: {
                HStack(spacing: 7) {
                    if isTesting {
                        ProgressView().controlSize(.small)
                    } else {
                        Circle()
                            .fill(session.reachability.tint)
                            .frame(width: 8, height: 8)
                    }
                    Text(session.reachability.label)
                        .font(.ocSubhead)
                        .foregroundStyle(session.reachability.tint)
                }
            })

            GroupedRow(title: "測試連線", titleTint: OC.accent, action: {
                isTesting = true
                Task {
                    await session.testConnection()
                    isTesting = false
                }
            })

            GroupedRow(title: "切換主機", isLast: true, trailing: {
                RowValue(text: "\(session.hosts.count) 組已存")
            }, action: { showHostSwitcher = true })
        }
    }

    // MARK: Security

    private var securitySection: some View {
        @Bindable var bindableSession = session
        return GroupedSection(
            header: "安全 SECURITY",
            footer: "改密碼會撤銷所有舊 session，其他裝置需要重新登入。"
        ) {
            GroupedRow(title: "\(Biometrics.available.label) 解鎖", trailing: {
                Toggle("", isOn: $bindableSession.useBiometrics)
                    .labelsHidden()
                    .tint(OC.toggleOn)
                    .disabled(Biometrics.available == .none)
                    .onChange(of: session.useBiometrics) { session.savePreferences() }
            })

            GroupedRow(title: "改密碼", trailing: {
                Icon(.chevronRight, size: 13).foregroundStyle(OC.labelQuaternary)
            }, action: { showChangePassword = true })

            GroupedRow(title: "登入有效期", trailing: {
                RowValue(text: "7 天", showsChevron: false)
            })

            GroupedRow(title: "登出這台裝置",
                       titleTint: OC.danger,
                       isLast: true,
                       action: { showSignOutConfirm = true })
        }
    }

    private var buildFooter: some View {
        HStack(spacing: 11) {
            BrandMark(size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.isDemo ? DemoData.studioName : "OffiCraft")
                    .font(.ocSubhead)
                    .foregroundStyle(OC.label)
                Text(session.serverVersion ?? (session.isDemo ? DemoData.buildVersion : "—"))
                    .font(.ocFootnoteSmall)
                    .foregroundStyle(OC.labelTertiary)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: OCMetrics.groupRadius, style: .continuous)
                .fill(OC.surface)
        )
    }
}

// MARK: - Host switcher

/// The saved connection targets, so leaving the house is one tap.
struct HostSwitcherView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var newHost = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    GroupedSection(header: "已存主機") {
                        ForEach(Array(session.hosts.enumerated()), id: \.element.id) { index, host in
                            GroupedRow(
                                title: host.label.isEmpty ? host.display : host.label,
                                isLast: index == session.hosts.count - 1,
                                trailing: {
                                    HStack(spacing: 8) {
                                        Text(host.scheme.uppercased())
                                            .font(.ocCaption)
                                            .foregroundStyle(OC.labelQuaternary)
                                        if host.id == session.activeHost?.id {
                                            Icon(.check, size: 15).foregroundStyle(OC.accent)
                                        }
                                    }
                                },
                                action: {
                                    Task {
                                        await session.switchHost(to: host)
                                        dismiss()
                                    }
                                }
                            )
                        }
                    }

                    GroupedSection(
                        header: "新增主機",
                        footer: "新增後要用 owner 密碼登入一次，之後就會記住。"
                    ) {
                        GroupedRow(title: "網址", isLast: true, trailing: {
                            TextField("127.0.0.1:7755", text: $newHost)
                                .font(.ocMono(14))
                                .foregroundStyle(OC.labelBody)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .frame(maxWidth: 190)
                        })
                    }

                    Button {
                        let host = ServerHost(raw: newHost, label: ServerHost(raw: newHost).display)
                        session.hosts.append(host)
                        session.savePreferences()
                        newHost = ""
                    } label: {
                        Text("加入清單")
                            .font(.ocCallout.weight(.semibold))
                            .foregroundStyle(newHost.isEmpty ? OC.labelQuaternary : OC.accent)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(newHost.isEmpty ? OC.surface : OC.accentFill)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(newHost.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(OCMetrics.screenPadding)
            }
            .background(OC.bg)
            .navigationTitle("切換主機")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Change password

struct ChangePasswordView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var current = ""
    @State private var updated = ""
    @State private var confirmation = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    private var canSave: Bool {
        !current.isEmpty && updated.count >= 8 && updated == confirmation && !isSaving
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    GroupedSection(
                        footer: "新密碼至少 8 個字元。存檔後所有舊 session 會被撤銷，其他裝置要重新登入。"
                    ) {
                        secureRow(title: "目前密碼", text: $current)
                        secureRow(title: "新密碼", text: $updated)
                        secureRow(title: "再輸入一次", text: $confirmation, isLast: true)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.ocFootnote)
                            .foregroundStyle(OC.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(OCMetrics.screenPadding)
            }
            .background(OC.bg)
            .navigationTitle("改密碼")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { save() }.disabled(!canSave)
                }
            }
        }
    }

    private func secureRow(title: String, text: Binding<String>, isLast: Bool = false) -> some View {
        GroupedRow(title: title, isLast: isLast, trailing: {
            SecureField("", text: text)
                .font(.ocCallout)
                .foregroundStyle(OC.labelBody)
                .multilineTextAlignment(.trailing)
                .textContentType(.password)
                .frame(maxWidth: 170)
        })
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await session.api.changePassword(old: current, new: updated)
                // Every old session is revoked, including this one.
                session.signOut()
                dismiss()
            } catch {
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
            isSaving = false
        }
    }
}
