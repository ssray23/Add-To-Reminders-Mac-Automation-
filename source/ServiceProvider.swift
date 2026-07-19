import Cocoa

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
                    parsedData = ParsedReminderData(title: parsedData.title, date: selectedDate, allDetectedDates: parsedData.allDetectedDates, url: parsedData.url, recurrence: parsedData.recurrence)
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
        var dateString = text
        if !parsedData.title.isEmpty {
            let wordCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
            let titleWords = parsedData.title.components(separatedBy: .whitespacesAndNewlines)
            for word in titleWords {
                guard !word.isEmpty else { continue }
                let escapedWord = NSRegularExpression.escapedPattern(for: word)
                
                let startsWithWordChar = word.first?.unicodeScalars.first.map { wordCharacters.contains($0) } ?? false
                let endsWithWordChar = word.last?.unicodeScalars.first.map { wordCharacters.contains($0) } ?? false
                
                let startBoundary = startsWithWordChar ? "\\b" : ""
                let endBoundary = endsWithWordChar ? "\\b" : ""
                let pattern = "(?i)\(startBoundary)\(escapedWord)\(endBoundary)"
                
                if let range = dateString.range(of: pattern, options: .regularExpression) {
                    dateString.replaceSubrange(range, with: "")
                }
            }
        }
        dateString = dateString.replacingOccurrences(of: "(?i)\\b(due|before|at|on|for|in|by|until)\\s*$", with: "", options: .regularExpression)
        dateString = dateString.replacingOccurrences(of: "^[\\s|&\\-]*|[\\s|&\\-]*$", with: "", options: .regularExpression)
        dateString = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if dateString.isEmpty {
            dateString = "Tomorrow at 7am"
        }
        
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
                    newParsedData = ParsedReminderData(title: newParsedData.title, date: selectedDate, allDetectedDates: newParsedData.allDetectedDates, url: newParsedData.url, recurrence: newParsedData.recurrence)
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
