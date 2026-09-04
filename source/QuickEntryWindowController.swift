import Cocoa
import SwiftUI
import EventKit

class QuickEntryPanel: NSPanel {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
}

class QuickEntryWindowController: NSWindowController, NSWindowDelegate {
    static let shared = QuickEntryWindowController()
    private var completion: (((title: String, dateText: String, selectedDate: Date?, url: String, listIdentifier: String?)?) -> Void)?
    
    init() {
        let rect = NSRect(x: 0, y: 0, width: 600, height: 210) // Will auto-resize due to SwiftUI
        let window = QuickEntryPanel(contentRect: rect,
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered,
                             defer: false)
        window.level = .floating
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.center()
        
        window.hasShadow = true
        window.backgroundColor = .clear
        window.isOpaque = false
        
        super.init(window: window)
        window.delegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func show(prompt: String, titlePlaceholder: String = "What do you want to be reminded about?", datePlaceholder: String = "e.g. tomorrow at 7am, in 3 hours, repeat weekly", initialTitle: String = "", initialDate: String = "", detectedDates: [Date] = [], completion: @escaping ((title: String, dateText: String, selectedDate: Date?, url: String, listIdentifier: String?)?) -> Void) {
        self.completion = completion
        
        NSApp.setActivationPolicy(.regular)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        
        let view = QuickEntryView(prompt: prompt, titlePlaceholder: titlePlaceholder, datePlaceholder: datePlaceholder, titleText: initialTitle, dateText: initialDate, detectedDates: detectedDates) { [weak self] result in
            self?.closeWindow()
            completion(result)
        }
        
        let hostingView = NSHostingView(rootView: view)
        self.window?.contentView = hostingView
        
        if let window = self.window {
            window.layoutIfNeeded()
            let fittingSize = hostingView.fittingSize
            let targetWidth: CGFloat = 600
            let targetHeight = max(fittingSize.height, 220)
            
            let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
            if let screen = screen {
                let screenFrame = screen.visibleFrame
                let newX = screenFrame.midX - (targetWidth / 2.0)
                let newY = max(screenFrame.minY + 20, min(screenFrame.midY - (targetHeight / 2.0), screenFrame.maxY - targetHeight - 20))
                window.setFrame(NSRect(x: newX, y: newY, width: targetWidth, height: targetHeight), display: true, animate: false)
            } else {
                window.center()
            }
            
            window.makeKeyAndOrderFront(nil)
        }
    }
    
    private func closeWindow() {
        self.window?.orderOut(nil)
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        closeWindow()
        completion?(nil)
        return true
    }
}

struct QuickEntryView: View {
    let prompt: String
    let titlePlaceholder: String
    let datePlaceholder: String
    @State var titleText: String
    @State var dateText: String
    let detectedDates: [Date]
    @State var selectedDate: Date?
    @State var urlText: String = ""
    
    @State var reminderLists: [EKCalendar] = []
    @State var selectedListIdentifier: String = ""
    
    let onComplete: (((title: String, dateText: String, selectedDate: Date?, url: String, listIdentifier: String?)?) -> Void)
    
    typealias Field = QuickEntryField
    @FocusState private var focusedField: Field?
    @State private var eventMonitor: Any? = nil
    
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()
    
    private let dateFormatterOnly: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()
    
    private var activeParsedData: ParsedReminderData? {
        let titleTrimmed = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let dateTrimmed = dateText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let combined = (titleTrimmed + " " + dateTrimmed).trimmingCharacters(in: .whitespacesAndNewlines)
        if combined.isEmpty {
            return nil
        }
        return TextParser.parse(text: combined)
    }
    
    private func updateDateTextFromTitleLive() {
        guard focusedField != .date else { return }
        let titleTrimmed = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !titleTrimmed.isEmpty else { return }
        
        let dateTrimmed = dateText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedTitle = TextParser.parse(text: titleTrimmed)
        
        if parsedTitle.date != nil || parsedTitle.recurrence != nil {
            if !dateTrimmed.isEmpty {
                let combined = "\(titleTrimmed) \(dateTrimmed)"
                let parsedCombined = TextParser.parse(text: combined)
                if let feedback = TextParser.formatParsedDateFeedback(parsedCombined) {
                    self.dateText = feedback
                }
            } else {
                if let feedback = TextParser.formatParsedDateFeedback(parsedTitle) {
                    self.dateText = feedback
                }
            }
        }
    }
    
    private var dateTextHasValidDate: Bool {
        let titleTrimmed = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let dateTrimmed = dateText.trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = (titleTrimmed + " " + dateTrimmed).trimmingCharacters(in: .whitespacesAndNewlines)
        if combined.isEmpty { return false }
        return TextParser.parse(text: combined).date != nil
    }
    
    @State private var isSeparating = false
    
    private func autoSeparateDateFromTitleIfNeeded() {
        guard !isSeparating else { return }
        let titleTrimmed = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !titleTrimmed.isEmpty else { return }
        
        let dateTrimmed = dateText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = TextParser.parse(text: titleTrimmed)
        
        if (parsed.date != nil || parsed.recurrence != nil) && parsed.title != titleTrimmed {
            var finalDateText = ""
            if !dateTrimmed.isEmpty {
                let combined = "\(titleTrimmed) \(dateTrimmed)"
                let parsedCombined = TextParser.parse(text: combined)
                finalDateText = TextParser.formatParsedDateFeedback(parsedCombined) ?? TextParser.formatParsedDateFeedback(parsed) ?? ""
            } else {
                finalDateText = TextParser.formatParsedDateFeedback(parsed) ?? ""
            }
            
            isSeparating = true
            self.titleText = parsed.title
            if !finalDateText.isEmpty {
                self.dateText = finalDateText
            }
            DispatchQueue.main.async {
                self.isSeparating = false
            }
        }
    }
    
    private var dynamicDetectedDates: [Date] {
        let titleTrimmed = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let dateTrimmed = dateText.trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = (titleTrimmed + " " + dateTrimmed).trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !combined.isEmpty {
            let parsed = TextParser.parse(text: combined)
            if parsed.allDetectedDates.count > 1 {
                return parsed.allDetectedDates
            }
        }
        return detectedDates
    }
    
    @State private var selectedIndex: Int = 0
    
    private var effectiveSelectedDate: Date? {
        let dates = dynamicDetectedDates
        if selectedIndex >= 0 && selectedIndex < dates.count {
            return dates[selectedIndex]
        }
        return dates.first
    }
    
    @ViewBuilder
    private var multipleDatesSection: some View {
        if dynamicDetectedDates.count > 1 {
            VStack(alignment: .leading, spacing: 10) {
                Text("Multiple dates detected. Which one would you like to use?")
                    .foregroundColor(.secondary)
                
                ForEach(0..<dynamicDetectedDates.count, id: \.self) { index in
                    DateOptionRowView(
                        isSelected: selectedIndex == index,
                        isFocused: focusedField == .date,
                        label: formatDateOptionLabel(dynamicDetectedDates[index]),
                        action: { selectDateOption(at: index) }
                    )
                }
                
                if let feedback = parsedDateFeedback {
                    Text(feedback)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                }
            }
            .padding(8)
            .background(focusedField == .date ? Color.accentColor.opacity(0.05) : Color.clear)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor.opacity(focusedField == .date ? 1.0 : 0.0), lineWidth: 2)
            )
            .focusable()
            .hideSystemFocusRing()
            .focused($focusedField, equals: .date)
        }
    }

    private func selectDateOption(at index: Int) {
        let dates = dynamicDetectedDates
        guard index >= 0 && index < dates.count else { return }
        selectedIndex = index
        selectedDate = dates[index]
        focusedField = .date
    }
    
    private func formatDateOptionLabel(_ date: Date) -> String {
        let titleTrimmed = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let dateTrimmed = dateText.trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = (titleTrimmed + " " + dateTrimmed).trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = TextParser.parse(text: combined)
        
        let formattedDate = dateFormatter.string(from: date)
        if let rec = parsed.recurrence {
            return "\(formattedDate) (\(TextParser.formatRecurrenceLabel(rec)))"
        }
        return formattedDate
    }
    
    private func dateOptionBorderOpacity(for index: Int) -> Double {
        if focusedField == .date && selectedIndex == index {
            return 1.0
        } else if selectedIndex == index {
            return 0.5
        } else {
            return 0.0
        }
    }
    
    private var parsedDateFeedback: String? {
        let dateTrimmed = dateText.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleTrimmed = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = (titleTrimmed + " " + dateTrimmed).trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedCombined = TextParser.parse(text: combined)
        
        if dynamicDetectedDates.count > 1, let selDate = effectiveSelectedDate {
            if parsedCombined.recurrence != nil {
                let dfOnly = DateFormatter()
                dfOnly.dateStyle = .medium
                dfOnly.timeStyle = .none
                let startDate = parsedCombined.date ?? selDate
                let startString = dateFormatter.string(from: startDate)
                let recLabel = TextParser.formatRecurrenceLabel(parsedCombined.recurrence!)
                return "Will set due date: \(startString) (\(recLabel) until \(dfOnly.string(from: selDate)))"
            } else {
                let selString = dateFormatter.string(from: selDate)
                return "Will set due date: \(selString)"
            }
        }
        
        guard let parsed = activeParsedData else { return nil }
        
        if let feedback = TextParser.formatParsedDateFeedback(parsed) {
            return "Will set due date: " + feedback
        } else if !dateTrimmed.isEmpty {
            return "⚠️ No date/time recognized (reminder will have no date)"
        } else {
            return nil
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(prompt)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            TextField(titlePlaceholder, text: $titleText)
                .textFieldStyle(PlainTextFieldStyle())
                .padding(12)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor.opacity(focusedField == .title ? 1.0 : 0.0), lineWidth: 2)
                )
                .focused($focusedField, equals: .title)
                .onChange(of: titleText) { _ in
                    updateDateTextFromTitleLive()
                }
                .onChange(of: focusedField) { newFocus in
                    if newFocus != .title {
                        autoSeparateDateFromTitleIfNeeded()
                    }
                }
                .onSubmit {
                    autoSeparateDateFromTitleIfNeeded()
                    onComplete((title: titleText, dateText: dateText, selectedDate: effectiveSelectedDate, url: urlText, listIdentifier: selectedListIdentifier.isEmpty ? nil : selectedListIdentifier))
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        focusedField = .title
                    }
                    autoSeparateDateFromTitleIfNeeded()
                    if dynamicDetectedDates.count > 1 {
                        selectedIndex = 0
                    }
                    fetchReminderLists()
                    setupKeyMonitor()
                }
                .onDisappear {
                    removeKeyMonitor()
                }
            
            multipleDatesSection
            
            if dynamicDetectedDates.count <= 1 {
                VStack(alignment: .leading, spacing: 6) {
                    TextField(datePlaceholder, text: $dateText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(12)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.accentColor.opacity(focusedField == .date ? 1.0 : 0.0), lineWidth: 2)
                        )
                        .focused($focusedField, equals: .date)
                        .onSubmit {
                            autoSeparateDateFromTitleIfNeeded()
                            onComplete((title: titleText, dateText: dateText, selectedDate: nil, url: urlText, listIdentifier: selectedListIdentifier.isEmpty ? nil : selectedListIdentifier))
                        }
                    
                    if let feedback = parsedDateFeedback {
                        Text(feedback)
                            .font(.system(size: 11))
                            .foregroundColor(dateTextHasValidDate ? .secondary : .orange)
                            .padding(.horizontal, 4)
                    }
                }
            }
                
            TextField("URL (Optional)", text: $urlText)
                .textFieldStyle(PlainTextFieldStyle())
                .padding(12)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor.opacity(focusedField == .url ? 1.0 : 0.0), lineWidth: 2)
                )
                .focused($focusedField, equals: .url)
                .onSubmit {
                    autoSeparateDateFromTitleIfNeeded()
                    onComplete((title: titleText, dateText: dateText, selectedDate: selectedDate, url: urlText, listIdentifier: selectedListIdentifier.isEmpty ? nil : selectedListIdentifier))
                }
            
            if !reminderLists.isEmpty {
                HStack(spacing: 12) {
                    Text("Add to List")
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Picker("", selection: $selectedListIdentifier) {
                        ForEach(reminderLists, id: \.calendarIdentifier) { list in
                            Text(list.title)
                                .tag(list.calendarIdentifier)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 250, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor.opacity(focusedField == .list ? 1.0 : 0.0), lineWidth: 2)
                )
                .focusable()
                .hideSystemFocusRing()
                .focused($focusedField, equals: .list)
                .onTapGesture {
                    focusedField = .list
                }
            }
            
            HStack {
                Spacer()
                Button(action: {
                    onComplete(nil)
                }) {
                    Text("Cancel")
                        .fontWeight(.medium)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.2))
                        .foregroundColor(.red)
                        .clipShape(Capsule())
                }
                .buttonStyle(PlainButtonStyle())
                .keyboardShortcut(.escape, modifiers: [])
                
                Button(action: {
                    autoSeparateDateFromTitleIfNeeded()
                    onComplete((title: titleText, dateText: dateText, selectedDate: effectiveSelectedDate, url: urlText, listIdentifier: selectedListIdentifier.isEmpty ? nil : selectedListIdentifier))
                }) {
                    Text("Add")
                        .fontWeight(.medium)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(PlainButtonStyle())
                .keyboardShortcut(.return, modifiers: [])
                .disabled(dynamicDetectedDates.count > 1 && effectiveSelectedDate == nil)
                .opacity(dynamicDetectedDates.count > 1 && effectiveSelectedDate == nil ? 0.5 : 1.0)
            }
        }
        .font(.system(size: 13))
        .padding(24)
        .frame(width: 600)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
        .cornerRadius(12)
    }
    
    private func setupKeyMonitor() {
        removeKeyMonitor()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let isShift = event.modifierFlags.contains(.shift)
            
            switch event.keyCode {
            case 48: // Tab key
                handleTabKey(isShift: isShift)
                return nil
                
            case 125: // Down arrow
                if focusedField == .date && dynamicDetectedDates.count > 1 {
                    selectedIndex = QuickEntryNavigationHelper.nextSelectionIndex(current: selectedIndex, delta: 1, total: dynamicDetectedDates.count)
                    selectedDate = dynamicDetectedDates[selectedIndex]
                    return nil
                } else if focusedField == .list && !reminderLists.isEmpty {
                    if let currentIndex = reminderLists.firstIndex(where: { $0.calendarIdentifier == selectedListIdentifier }) {
                        let nextIndex = QuickEntryNavigationHelper.nextSelectionIndex(current: currentIndex, delta: 1, total: reminderLists.count)
                        selectedListIdentifier = reminderLists[nextIndex].calendarIdentifier
                    }
                    return nil
                }
                return event
                
            case 126: // Up arrow
                if focusedField == .date && dynamicDetectedDates.count > 1 {
                    selectedIndex = QuickEntryNavigationHelper.nextSelectionIndex(current: selectedIndex, delta: -1, total: dynamicDetectedDates.count)
                    selectedDate = dynamicDetectedDates[selectedIndex]
                    return nil
                } else if focusedField == .list && !reminderLists.isEmpty {
                    if let currentIndex = reminderLists.firstIndex(where: { $0.calendarIdentifier == selectedListIdentifier }) {
                        let prevIndex = QuickEntryNavigationHelper.nextSelectionIndex(current: currentIndex, delta: -1, total: reminderLists.count)
                        selectedListIdentifier = reminderLists[prevIndex].calendarIdentifier
                    }
                    return nil
                }
                return event
                
            default:
                return event
            }
        }
    }
    
    private func removeKeyMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    private func handleTabKey(isShift: Bool) {
        focusedField = QuickEntryNavigationHelper.nextField(from: focusedField, isShift: isShift, hasLists: !reminderLists.isEmpty)
    }
    
    private func fetchReminderLists() {
        RemindersManager.shared.requestAccess { granted in
            if granted {
                let lists = RemindersManager.shared.getReminderLists()
                DispatchQueue.main.async {
                    self.reminderLists = lists
                    let firstName = RemindersManager.userFirstName.lowercased()
                    let targets = RemindersManager.targetListNames
                    if let targetList = lists.first(where: { $0.title.lowercased() == firstName }) ??
                                       lists.first(where: { targets.contains($0.title.replacingOccurrences(of: "’", with: "'").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }) {
                        self.selectedListIdentifier = targetList.calendarIdentifier
                    } else if let defaultList = RemindersManager.shared.eventStore.defaultCalendarForNewReminders() {
                        self.selectedListIdentifier = defaultList.calendarIdentifier
                    } else if let firstList = lists.first {
                        self.selectedListIdentifier = firstList.calendarIdentifier
                    }
                }
            }
        }
    }
}

struct DateOptionRowView: View {
    let isSelected: Bool
    let isFocused: Bool
    let label: String
    let action: () -> Void
    
    private var borderOpacity: Double {
        if isFocused && isSelected {
            return 1.0
        } else if isSelected {
            return 0.5
        } else {
            return 0.0
        }
    }
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                Text(label)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(8)
            .background(Color(NSColor.textBackgroundColor).opacity(isSelected ? 1.0 : 0.6))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor.opacity(borderOpacity), lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct HideFocusRingModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.focusEffectDisabled()
        } else {
            content
        }
    }
}

extension View {
    func hideSystemFocusRing() -> some View {
        self.modifier(HideFocusRingModifier())
    }
}





