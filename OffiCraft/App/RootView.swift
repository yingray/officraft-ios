import SwiftUI

/// Which of the five sections is showing. Shared by the iPhone tab bar and the
/// iPad sidebar so deep links land in the same place on both.
enum AppSection: String, CaseIterable, Identifiable {
    case asks, tasks, office, monitor, more
    var id: String { rawValue }

    var title: String {
        switch self {
        case .asks: return "請示"
        case .tasks: return "任務"
        case .office: return "辦公室"
        case .monitor: return "監控"
        case .more: return "更多"
        }
    }

    var icon: OCIcon {
        switch self {
        case .asks: return .inbox
        case .tasks: return .tasks
        case .office: return .office
        case .monitor: return .monitor
        case .more: return .ellipsis
        }
    }
}

struct RootView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Group {
            switch session.phase {
            case .loading:
                LaunchView()
            case .signedOut:
                LoginView()
            case .locked:
                LockedView()
            case .signedIn, .demo:
                StudioView()
            }
        }
        .animation(.smooth(duration: 0.25), value: session.phase)
    }
}

/// Brief placeholder while the keychain is read.
private struct LaunchView: View {
    var body: some View {
        ZStack {
            OC.bg.ignoresSafeArea()
            BrandMark(size: 64).opacity(0.9)
        }
    }
}

/// Token present, biometric gate not yet passed.
private struct LockedView: View {
    @Environment(AppSession.self) private var session
    @State private var failed = false

    var body: some View {
        ZStack {
            OC.bg.ignoresSafeArea()
            VStack(spacing: 22) {
                BrandMark(size: 64)
                VStack(spacing: 6) {
                    Text("OffiCraft")
                        .font(.ocDisplay)
                        .foregroundStyle(OC.label)
                    Text(session.activeHost?.display ?? "")
                        .font(.ocMono(13))
                        .foregroundStyle(OC.labelTertiary)
                }
                Button {
                    Task { failed = !(await session.unlock()) }
                } label: {
                    HStack(spacing: 9) {
                        Icon(.faceID, size: 19)
                        Text("用 \(Biometrics.available.label) 解鎖")
                            .font(.ocBodyLarge.weight(.semibold))
                    }
                    .foregroundStyle(OC.accent)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(OC.accentFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(OC.accentBorder, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 40)

                if failed {
                    Text("解鎖沒過，可以再試一次，或改用密碼重新連線。")
                        .font(.ocFootnote)
                        .foregroundStyle(OC.labelTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                Button("改用密碼重新連線") { session.signOut() }
                    .font(.ocFootnote)
                    .foregroundStyle(OC.labelTertiary)
            }
        }
        .task {
            // Present the prompt straight away — the owner opened the app to
            // deal with something, not to tap an extra button.
            failed = !(await session.unlock())
        }
    }
}

// MARK: - Signed-in shell

private struct StudioView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var store: StudioStore?
    @State private var section: AppSection = .asks

    var body: some View {
        Group {
            if let store {
                content(store: store)
                    .environment(store)
                    .task { await store.loadAll() }
            } else {
                Color.clear
            }
        }
        .onAppear {
            if store == nil { store = StudioStore(session: session) }
        }
    }

    @ViewBuilder
    private func content(store: StudioStore) -> some View {
        // The doc's iPad layout is sidebar → list → detail; on iPhone the same
        // five sections live in a tab bar.
        if sizeClass == .regular {
            SplitRootView(section: $section)
        } else {
            TabRootView(section: $section)
        }
    }
}
