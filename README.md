# OffiCraft iOS

Native iOS cockpit for [OffiCraft](https://github.com/pkyosx/OffiCraft) — the AI
studio that runs on your own Mac. Built from the `OffiCraft iOS.dc.html` design
doc.

Asks (請示) are the point: decide from the inbox, one card at a time, options
tappable in place. Tasks (任務) are progress-first — which step it is on, and
what it is blocked behind. Everything an agent writes renders as full markdown.

## Requirements

- Xcode 16 or later (iOS 17 SDK)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

## Build

```bash
xcodegen generate          # regenerate OffiCraft.xcodeproj from project.yml
open OffiCraft.xcodeproj
```

The `.xcodeproj` is generated, not checked in. Edit `project.yml` and
regenerate rather than changing project settings in the Xcode UI.

### Unsigned .ipa

```bash
./scripts/build-ipa.sh
```

Produces `dist/OffiCraft.ipa`. The build is unsigned — enough to inspect,
resign, or side-load with your own certificate. To install on a device, resign
with a provisioning profile that includes the app and its widget extension.

## Layout

| Path | What lives there |
| --- | --- |
| `OffiCraft/App` | Entry point, session, store, shells (tab / split) |
| `OffiCraft/Design` | Colour tokens, type scale, SVG icon set, shared components |
| `OffiCraft/Models` | Wire models and the eight-state task vocabulary |
| `OffiCraft/Networking` | REST client, SSE stream, keychain, biometrics |
| `OffiCraft/Markdown` | Block parser, syntax highlighter, renderer |
| `OffiCraft/Features` | One folder per screen group |
| `OffiCraft/Notifications` | Push categories, Live Activity control |
| `OffiCraft/Demo` | The design doc's sample studio |
| `OffiCraftWidgets` | Live Activity (Lock Screen + Dynamic Island) |

## Screens

Every screen in the design doc, and where it is implemented:

| Design doc | Implementation |
| --- | --- |
| 登入 · Host + 密碼 | `Features/Auth/LoginView.swift` |
| 設定 · 連線與安全 | `Features/More/ConnectionSettingsView.swift` |
| 請示 · 收件匣（深／淺） | `Features/Asks/AsksView.swift`, `AskCardView.swift` |
| 請示 · 單卡決策 | `Features/Asks/AskDetailView.swift` |
| 請示 · 近期已處理 | `Features/Asks/AskCardView.swift` (`HandledAskCardView`) |
| 任務 · 清單 | `Features/Tasks/TasksView.swift`, `TaskRowView.swift` |
| 任務 · 詳情 | `Features/Tasks/TaskDetailView.swift` |
| 辦公室 · 成員名單 | `Features/Office/OfficeView.swift` |
| 聊天 · Markdown 訊息 | `Features/Office/ChatView.swift` |
| 監控 | `Features/Monitor/MonitorView.swift` |
| 更多 · 設定與偏好 | `Features/More/MoreView.swift` |
| 附件 · 觸發點 | `Features/Attachments/AttachmentStrip.swift` |
| 圖片 · 全螢幕預覽 | `Features/Attachments/AttachmentPreview.swift` |
| Markdown 檔 · 全文預覽 | `Features/Attachments/AttachmentPreview.swift` |
| 推播與鎖定畫面 | `Notifications/NotificationManager.swift` |
| 任務進度 · Live Activity | `OffiCraftWidgets/TaskLiveActivity.swift` |
| iPad · 請示三欄 | `Features/iPad/SplitRootView.swift` |

## Design system

Semantic colours come from the console's `theme.css` and resolve per
appearance, so the light and dark screens in the doc are one definition:

| Token | Means |
| --- | --- |
| `OC.accent` | 進行中／已完成／AI 建議 |
| `OC.waiting` | 等我回覆 — the only colour allowed to interrupt you |
| `OC.external` | 等待外部 |
| `OC.taskNo` / `OC.taskType` | 任務編號 / 任務類型 |
| `OC.danger` / `OC.frozen` | 高優先／終止 / 凍結／依賴 |

Icons are the web console's `components/icons.tsx` paths, parsed at runtime by
`Design/SVGPath.swift` rather than redrawn — a change on the web side is a
copy-paste, not a re-trace.

## Server contract

- REST per `spec/openapi.json`; the client is in `Networking/Endpoints.swift`.
- SSE per `spec/sse.md`: no cursor, no replay, reconcile by refetch, full
  resync on every reconnect.
- The server binds `127.0.0.1` by default. To reach it from a phone, run your
  own tunnel (cloudflared) or a VPN — the login screen says so too.

## Demo studio

`先用示範資料看看` on the login screen loads the design doc's sample studio —
Kyle, Sasha, Mira, 外包 O-7, three waiting cards, the pagination task with its
gate step. No server needed. Useful for review and for screenshots.

## Notes and limits

- Type sizes are fixed to the doc's point values rather than scaling with
  Dynamic Type. Layout is all stacks, so it reflows, but text does not grow.
- The machine card reports CPU and RAM as percentages: the wire carries
  `cpu_pct` / `ram_pct` only, not the absolute `11.4／16 GB` the mock shows.
- 角色誌 / 任務手冊 / 參數調整 / 使用說明 are authoring surfaces that stay in the
  web console; the app links out instead of shipping a stub.
- Attachment upload from the composer is not wired yet — the `+` button is
  present, the picker is not.
