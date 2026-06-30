import Foundation

class NotificationHelper {
    static func showNotification(title: String, date: Date?) {
        var subtitle = "No due date"
        
        if let date = date {
            let calendar = Calendar.current
            
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "h:mm a"
            let timeString = timeFormatter.string(from: date).lowercased() // matches "am/pm" format from applescript
            
            var dayLabel = ""
            if calendar.isDateInToday(date) {
                dayLabel = "Today"
            } else if calendar.isDateInTomorrow(date) {
                dayLabel = "Tomorrow"
            } else {
                let day = calendar.component(.day, from: date)
                let numberFormatter = NumberFormatter()
                numberFormatter.numberStyle = .ordinal
                let dayString = numberFormatter.string(from: NSNumber(value: day)) ?? "\(day)"
                
                let monthYearFormatter = DateFormatter()
                monthYearFormatter.dateFormat = "MMMM yyyy"
                let monthYearString = monthYearFormatter.string(from: date)
                
                dayLabel = "\(dayString) \(monthYearString)"
            }
            
            subtitle = "\(dayLabel), \(timeString)"
        }
        
        // Escape quotes for AppleScript
        let safeTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let safeSubtitle = subtitle.replacingOccurrences(of: "\"", with: "\\\"")
        
        let script = "tell application \"Reminders\" to display notification \"\(safeSubtitle)\" with title \"\(safeTitle)\""
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }
}
