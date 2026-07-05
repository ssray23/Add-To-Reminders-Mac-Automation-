import Cocoa

@objc class ServiceProvider: NSObject {
    private var isShowingAlert = false

    @objc func showQuickEntry() {
        if isShowingAlert { return }
        isShowingAlert = true
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
            
            let alert = NSAlert()
            alert.messageText = "New Reminder"
            alert.informativeText = "What do you want to be reminded about?"
            alert.icon = NSWorkspace.shared.icon(forFile: "/System/Applications/Reminders.app")
            
            alert.addButton(withTitle: "Add")
            let cancelButton = alert.addButton(withTitle: "Cancel")
            if #available(macOS 11.0, *) {
                cancelButton.hasDestructiveAction = true
            }
            
            let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 330, height: 24))
            input.placeholderString = "e.g. Call John tomorrow at 7am"
            
            alert.accessoryView = input
            alert.layout()
            alert.window.makeKeyAndOrderFront(nil)
            alert.window.makeFirstResponder(input)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let textView = input.currentEditor() as? NSTextView {
                    textView.insertionPointColor = NSColor.textColor
                    textView.updateInsertionPointStateAndRestartTimer(true)
                }
            }
            
            let response = alert.runModal()
            
            self.isShowingAlert = false
            
            if response == .alertFirstButtonReturn {
                let text = input.stringValue
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    NSApp.hide(nil)
                    return
                }
                
                let parsedData = TextParser.parse(text: text)
                self.proceedWithSaving(parsedData: parsedData)
            } else {
                NSApp.hide(nil)
            }
            NSApp.setActivationPolicy(.accessory)
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
            NSApp.setActivationPolicy(.regular)
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
            
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
            alert.layout()
            alert.window.makeKeyAndOrderFront(nil)
            alert.window.makeFirstResponder(input)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let textView = input.currentEditor() as? NSTextView {
                    textView.insertionPointColor = NSColor.textColor
                    textView.updateInsertionPointStateAndRestartTimer(true)
                }
            }
            
            let response = alert.runModal()
            self.isShowingAlert = false
            
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
            NSApp.setActivationPolicy(.accessory)
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
