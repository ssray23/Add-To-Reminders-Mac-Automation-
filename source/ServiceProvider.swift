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
            QuickEntryWindowController.shared.show(prompt: "What do you want to be reminded about?",
                                                   placeholder: "e.g. Call John tomorrow at 7am") { [weak self] result in
                guard let self = self else { return }
                self.isShowingAlert = false
                
                guard let resultTuple = result, !resultTuple.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    self.logDebug("showQuickEntry: canceled or empty text")
                    NSApp.hide(nil)
                    return
                }
                
                var parsedData = TextParser.parse(text: resultTuple.text)
                self.logDebug("showQuickEntry: parsed text, url is \(String(describing: parsedData.url))")
                self.logDebug("showQuickEntry: urlText from UI is '\(resultTuple.url)'")
                
                if !resultTuple.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    var finalUrlString = resultTuple.url.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !finalUrlString.lowercased().hasPrefix("http") {
                        finalUrlString = "https://" + finalUrlString
                    }
                    if let newUrl = URL(string: finalUrlString) {
                        self.logDebug("showQuickEntry: Successfully created newUrl: \(newUrl)")
                        parsedData = ParsedReminderData(title: parsedData.title, date: parsedData.date, url: newUrl, recurrence: parsedData.recurrence)
                    } else {
                        self.logDebug("showQuickEntry: Failed to create URL from string: \(finalUrlString)")
                    }
                }
                
                self.logDebug("showQuickEntry: Proceeding to save with URL: \(String(describing: parsedData.url))")
                self.proceedWithSaving(parsedData: parsedData)
            }
        }
    }
    
    @objc func processText(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let text = pboard.string(forType: .string) else {
            return
        }
        
        let parsedData = TextParser.parse(text: text)
        
        if parsedData.date == nil {
            self.promptForDate(parsedData: parsedData)
        } else {
            DispatchQueue.main.async {
                self.proceedWithSaving(parsedData: parsedData)
            }
        }
    }
    
    private func promptForDate(parsedData: ParsedReminderData) {
        if isShowingAlert { return }
        isShowingAlert = true
        DispatchQueue.main.async {
            QuickEntryWindowController.shared.show(prompt: "When to remind you? (Clear text for 'No Date')",
                                                   placeholder: "e.g. tomorrow at 7am repeat weekly",
                                                   initialText: "Tomorrow at 7am") { [weak self] result in
                guard let self = self else { return }
                self.isShowingAlert = false
                
                guard let resultTuple = result else {
                    self.logDebug("promptForDate: canceled")
                    return
                }
                
                let text = resultTuple.text
                var finalUrl = parsedData.url
                
                self.logDebug("promptForDate: UI urlText = '\(resultTuple.url)', initial finalUrl = \(String(describing: finalUrl))")
                
                if !resultTuple.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    var finalUrlString = resultTuple.url.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !finalUrlString.lowercased().hasPrefix("http") {
                        finalUrlString = "https://" + finalUrlString
                    }
                    if let newUrl = URL(string: finalUrlString) {
                        self.logDebug("promptForDate: Successfully created newUrl: \(newUrl)")
                        finalUrl = newUrl
                    } else {
                        self.logDebug("promptForDate: Failed to create URL from string: \(finalUrlString)")
                    }
                }
                
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // No Date
                    self.logDebug("promptForDate: No date. Proceeding with URL: \(String(describing: finalUrl))")
                    let finalData = ParsedReminderData(title: parsedData.title, date: parsedData.date, url: finalUrl, recurrence: parsedData.recurrence)
                    self.proceedWithSaving(parsedData: finalData)
                } else {
                    // Set Date
                    let manualParsed = TextParser.parse(text: text)
                    self.logDebug("promptForDate: Date set. Proceeding with URL: \(String(describing: finalUrl))")
                    let finalData = ParsedReminderData(title: parsedData.title, date: manualParsed.date, url: finalUrl, recurrence: parsedData.recurrence ?? manualParsed.recurrence)
                    self.proceedWithSaving(parsedData: finalData)
                }
            }
        }
    }
    
    private func proceedWithSaving(parsedData: ParsedReminderData) {
        // Hide the app so the previous app gets focus back immediately
        NSApp.hide(nil)
        
        HUDWindowController.shared.show(state: .processing)
        
        RemindersManager.shared.requestAccess { granted in
            guard granted else {
                DispatchQueue.main.async {
                    HUDWindowController.shared.show(state: .error("No Access to Reminders"))
                }
                return
            }
            
            RemindersManager.shared.createReminder(data: parsedData) { success in
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
