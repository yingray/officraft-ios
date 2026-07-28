import Foundation

/// Date and duration wording, kept in one place so the same phrasing appears on
/// every surface — card, task row, notification, Live Activity.
enum OCFormat {

    private static let calendar = Calendar.current

    /// "7/29 09:05"
    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hant_TW")
        formatter.setLocalizedDateFormatFromTemplate("M/d HH:mm")
        return formatter.string(from: date)
    }

    /// "09:02" — message times inside a day group.
    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hant_TW")
        formatter.setLocalizedDateFormatFromTemplate("HH:mm")
        return formatter.string(from: date)
    }

    /// "今天 7/29" / "昨天 7/28" / "7/26 星期六" — the chat day separator.
    static func daySeparator(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hant_TW")
        if calendar.isDateInToday(date) {
            formatter.setLocalizedDateFormatFromTemplate("M/d")
            return "今天 \(formatter.string(from: date))"
        }
        if calendar.isDateInYesterday(date) {
            formatter.setLocalizedDateFormatFromTemplate("M/d")
            return "昨天 \(formatter.string(from: date))"
        }
        formatter.setLocalizedDateFormatFromTemplate("M/d EEEE")
        return formatter.string(from: date)
    }

    /// "42 分" / "1 小時 35 分" / "3 天 2 小時".
    ///
    /// Two units at most: past an hour the minutes stop mattering, past a day
    /// the minutes are noise.
    static func duration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let minutes = total / 60
        let hours = minutes / 60
        let days = hours / 24

        if days > 0 {
            let remainingHours = hours % 24
            return remainingHours > 0 ? "\(days) 天 \(remainingHours) 小時" : "\(days) 天"
        }
        if hours > 0 {
            let remainingMinutes = minutes % 60
            return remainingMinutes > 0 ? "\(hours) 小時 \(remainingMinutes) 分" : "\(hours) 小時"
        }
        if minutes > 0 { return "\(minutes) 分" }
        return "剛剛"
    }

    /// "已等你 42 分" — the amber line on a waiting reply card.
    static func waited(since date: Date, now: Date = .now) -> String {
        "已等你 \(duration(now.timeIntervalSince(date)))"
    }

    /// "已歷時 3 天 2 小時" — elapsed time on a task.
    static func elapsed(since date: Date, now: Date = .now) -> String {
        "已歷時 \(duration(now.timeIntervalSince(date)))"
    }

    /// "已於 7/29 07:48 回覆"
    static func answered(at date: Date) -> String {
        "已於 \(stamp(date)) 回覆"
    }

    /// "7/29 02:10 過期"
    static func expired(at date: Date) -> String {
        "\(stamp(date)) 過期"
    }

    /// "86%" — usage meters and progress readouts.
    static func percent(_ fraction: Double?) -> String {
        guard let fraction else { return "—" }
        return "\(Int((fraction * 100).rounded()))%"
    }

    /// "11.4／16 GB" — the machine card's RAM readout.
    static func gigabytes(used: Double, total: Double) -> String {
        String(format: "%.1f／%.0f GB", used, total)
    }

    /// "12.4 KB" — attachment sizes.
    static func fileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
