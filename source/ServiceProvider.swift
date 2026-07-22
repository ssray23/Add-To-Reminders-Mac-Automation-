import Cocoa
import EventKit

@objc class ServiceProvider: NSObject {
    private var isShowingAlert = false

    func logDebug(_ message: String) {
        let url = URL(fileURLWithPath: "/tmp/addtoreminders_debug.log")
        let text = "\(Date()): \(message)\n"
        if let data = text.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path) {
                if let fileHandle = try? FileHandle(forWritingTo: url) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: url)
            }
        }
    }

    @objc func showQuickEntry() {
        if isShowingAlert { return }
        isShowingAlert = true
        DispatchQueue.main.async {
            QuickEntryWindowController.shared.show(prompt: "What do you want to be reminded about?") { [weak self] result in
                guard let self = self else { return }
                self.isShowingAlert = false
                
                guard let resultTuple = result, !(resultTuple.title + resultTuple.dateText).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    self.logDebug("showQuickEntry: canceled or empty text")
                    NSApp.setActivationPolicy(.accessory)
                    NSApp.hide(nil)
                    return
                }
                
                let combinedText = resultTuple.title + " " + resultTuple.dateText
                var parsedData = TextParser.parse(text: combinedText)
                
                if let selectedDate = resultTuple.selectedDate {
                    parsedData = self.applySelectedDate(selectedDate: selectedDate, to: parsedData, originalParsedData: nil)
                }
                
                self.logDebug("showQuickEntry: parsed text, url is \(String(describing: parsedData.url))")
                self.logDebug("showQuickEntry: urlText from UI is '\(resultTuple.url)'")
                
                if !resultTuple.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    var finalUrlString = resultTuple.url.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !finalUrlString.lowercased().hasPrefix("http") {
                        finalUrlString = "https://" + finalUrlString
                    }
                    if let newUrl = URL(string: finalUrlString) {
                        self.logDebug("showQuickEntry: Successfully created newUrl: \(newUrl)")
                        parsedData = ParsedReminderData(title: parsedData.title, date: parsedData.date, allDetectedDates: parsedData.allDetectedDates, url: newUrl, recurrence: parsedData.recurrence)
                    } else {
                        self.logDebug("showQuickEntry: Failed to create URL from string: \(finalUrlString)")
                    }
                }
                
                self.logDebug("showQuickEntry: Proceeding to save with URL: \(String(describing: parsedData.url))")
                self.proceedWithSaving(parsedData: parsedData, listIdentifier: resultTuple.listIdentifier)
            }
        }
    }
    
    @objc func processText(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let text = pboard.string(forType: .string) else {
            return
        }
        
        let parsedData = TextParser.parse(text: text)
        let dateString = TextParser.formatParsedDateFeedback(parsedData) ?? ""
        
        if isShowingAlert { return }
        isShowingAlert = true
        DispatchQueue.main.async {
            QuickEntryWindowController.shared.show(prompt: "Add to Reminders",
                                                   initialTitle: parsedData.title,
                                                   initialDate: dateString,
                                                   detectedDates: parsedData.allDetectedDates) { [weak self] result in
                guard let self = self else { return }
                self.isShowingAlert = false
                
                guard let resultTuple = result, !(resultTuple.title + resultTuple.dateText).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    self.logDebug("processText: canceled or empty text")
                    NSApp.setActivationPolicy(.accessory)
                    NSApp.hide(nil)
                    return
                }
                
                let combinedText = resultTuple.title + " " + resultTuple.dateText
                var newParsedData = TextParser.parse(text: combinedText)
                
                if let selectedDate = resultTuple.selectedDate {
                    newParsedData = self.applySelectedDate(selectedDate: selectedDate, to: newParsedData, originalParsedData: parsedData)
                }
                
                // Preserve URL from original parse if not modified, or from UI
                var finalUrl = parsedData.url
                if !resultTuple.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    var finalUrlString = resultTuple.url.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !finalUrlString.lowercased().hasPrefix("http") {
                        finalUrlString = "https://" + finalUrlString
                    }
                    if let newUrl = URL(string: finalUrlString) {
                        finalUrl = newUrl
                    }
                }
                
                newParsedData = ParsedReminderData(title: newParsedData.title, date: newParsedData.date, allDetectedDates: newParsedData.allDetectedDates, url: finalUrl, recurrence: newParsedData.recurrence)
                
                self.proceedWithSaving(parsedData: newParsedData, listIdentifier: resultTuple.listIdentifier)
            }
        }
    }
    
    private func promptForDateSelection(parsedData: ParsedReminderData, dates: [Date], listIdentifier: String? = nil) {
        if isShowingAlert { return }
        isShowingAlert = true
        DispatchQueue.main.async {
            DateSelectionWindowController.shared.show(dates: dates) { [weak self] selectedDate in
                guard let self = self else { return }
                self.isShowingAlert = false
                
                guard let selectedDate = selectedDate else {
                    self.logDebug("promptForDateSelection: canceled")
                    NSApp.setActivationPolicy(.accessory)
                    NSApp.hide(nil)
                    return
                }
                
                self.logDebug("promptForDateSelection: Date selected. Proceeding with URL: \(String(describing: parsedData.url))")
                let finalData = ParsedReminderData(title: parsedData.title, date: selectedDate, allDetectedDates: parsedData.allDetectedDates, url: parsedData.url, recurrence: parsedData.recurrence)
                self.proceedWithSaving(parsedData: finalData, listIdentifier: listIdentifier)
            }
        }
    }
    
    private func applySelectedDate(selectedDate: Date, to parsedData: ParsedReminderData, originalParsedData: ParsedReminderData?) -> ParsedReminderData {
        var startDate = selectedDate
        var recRule = parsedData.recurrence ?? originalParsedData?.recurrence
        
        let hasExplicitRecurrence = (parsedData.recurrence != nil || originalParsedData?.recurrence != nil)
        if hasExplicitRecurrence && !Calendar.current.isDateInToday(selectedDate) {
            recRule = EKRecurrenceRule(recurrenceWith: .daily, interval: 1, daysOfTheWeek: nil, daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: EKRecurrenceEnd(end: TextParser.endOfDay(for: selectedDate)))
            var startComps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            startComps.hour = 7
            startComps.minute = 0
            startComps.second = 0
            if let s = Calendar.current.date(from: startComps) {
                startDate = s
            }
        }
        
        return ParsedReminderData(title: parsedData.title, date: startDate, allDetectedDates: parsedData.allDetectedDates, url: parsedData.url, recurrence: recRule, datePhrase: parsedData.datePhrase)
    }
    
    private func proceedWithSaving(parsedData: ParsedReminderData, listIdentifier: String? = nil) {
        // Hide the app so the previous app gets focus back immediately
        NSApp.setActivationPolicy(.accessory)
        NSApp.hide(nil)
        
        HUDWindowController.shared.show(state: .processing)
        
        RemindersManager.shared.requestAccess { granted in
            guard granted else {
                DispatchQueue.main.async {
                    HUDWindowController.shared.show(state: .error("No Access to Reminders"))
                }
                return
            }
            
            RemindersManager.shared.createReminder(data: parsedData, listIdentifier: listIdentifier) { success in
                DispatchQueue.main.async {
                    if success {
                        NotificationHelper.showNotification(title: parsedData.title, date: parsedData.date)
                        HUDWindowController.shared.show(state: .success(parsedData))
                    } else {
                        HUDWindowController.shared.show(state: .error("Failed to create reminder"))
                    }
                }
            }
        }
    }
}
