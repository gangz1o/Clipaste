import Foundation

extension Date {
    /// 返回 "HH:mm" 格式的时间字符串，如 "22:30"
    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: self)
    }

    /// 返回智能日期字符串：
    /// - 今天 → "今天"
    /// - 昨天 → "昨天"
    /// - 今年内 → "MM/dd"
    /// - 跨年 → "yyyy/MM/dd"
    var dateString: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            return String(localized: "今天")
        }
        if calendar.isDateInYesterday(self) {
            return String(localized: "昨天")
        }

        let formatter = DateFormatter()
        if calendar.isDate(self, equalTo: Date(), toGranularity: .year) {
            formatter.dateFormat = "MM/dd"
        } else {
            formatter.dateFormat = "yyyy/MM/dd"
        }
        return formatter.string(from: self)
    }
}
