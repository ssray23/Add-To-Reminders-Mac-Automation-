import Cocoa

@objc class ServiceProvider: NSObject {
    @objc func processText(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let text = pboard.string(forType: .string) else {
            return
        }
        
        let parsedData = TextParser.parse(text: text)
        
        if parsedData.date == nil {
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                
                let alert = NSAlert()
                alert.messageText = "When to remind you?"
                alert.informativeText = "Type naturally (e.g. 'tomorrow at 5pm', 'July 12th repeat daily')."
                alert.icon = NSWorkspace.shared.icon(forFile: "/System/Applications/Reminders.app")
                
                // Buttons are arranged right-to-left in macOS
                alert.addButton(withTitle: "Set Date")
                alert.addButton(withTitle: "No Date")
                alert.addButton(withTitle: "Cancel")
                
                let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
                input.placeholderString = "e.g. tomorrow at 7am repeat weekly"
                input.stringValue = "Tomorrow at 7am"
                
                alert.accessoryView = input
                
                let response = alert.runModal()
                
                if response == .alertFirstButtonReturn {
                    // Set Date
                    let manualInput = input.stringValue
                    let manualParsed = TextParser.parse(text: manualInput)
                    
                    let finalData = ParsedReminderData(title: parsedData.title, date: manualParsed.date, url: parsedData.url, recurrence: parsedData.recurrence ?? manualParsed.recurrence)
                    self.proceedWithSaving(parsedData: finalData)
                } else if response == .alertSecondButtonReturn {
                    // No Date
                    self.proceedWithSaving(parsedData: parsedData)
                } else {
                    // Cancel - do nothing and let the service stay running
                }
            }
        } else {
            DispatchQueue.main.async {
                self.proceedWithSaving(parsedData: parsedData)
            }
        }
    }
    
    private func proceedWithSaving(parsedData: ParsedReminderData) {
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
