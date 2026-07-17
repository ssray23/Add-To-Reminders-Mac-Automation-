import Cocoa
import SwiftUI

class QuickEntryPanel: NSPanel {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
}

class QuickEntryWindowController: NSWindowController, NSWindowDelegate {
    static let shared = QuickEntryWindowController()
    private var completion: (((title: String, dateText: String, selectedDate: Date?, url: String)?) -> Void)?
    
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
    
    func show(prompt: String, titlePlaceholder: String = "What do you want to be reminded about?", datePlaceholder: String = "e.g. tomorrow at 7am repeat weekly", initialTitle: String = "", initialDate: String = "", detectedDates: [Date] = [], completion: @escaping ((title: String, dateText: String, selectedDate: Date?, url: String)?) -> Void) {
        self.completion = completion
        
        NSApp.setActivationPolicy(.regular)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        
        self.window?.makeKeyAndOrderFront(nil)
        
        let view = QuickEntryView(prompt: prompt, titlePlaceholder: titlePlaceholder, datePlaceholder: datePlaceholder, titleText: initialTitle, dateText: initialDate, detectedDates: detectedDates) { [weak self] result in
            self?.closeWindow()
            completion(result)
        }
        
        self.window?.contentView = NSHostingView(rootView: view)
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
    let onComplete: (((title: String, dateText: String, selectedDate: Date?, url: String)?) -> Void)
    
    enum Field {
        case title
        case date
        case url
    }
    @FocusState private var focusedField: Field?
    
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(prompt)
                .font(.headline)
                .foregroundColor(.primary)
            
            TextField(titlePlaceholder, text: $titleText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 18))
                .padding(12)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor.opacity(focusedField == .title ? 1.0 : 0.0), lineWidth: 2)
                )
                .focused($focusedField, equals: .title)
                .onSubmit {
                    onComplete((title: titleText, dateText: dateText, selectedDate: selectedDate, url: urlText))
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        focusedField = .title
                    }
                    if let first = detectedDates.first, detectedDates.count > 1 {
                        selectedDate = first
                    }
                }
                
            if detectedDates.count > 1 {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Multiple dates detected. Which one would you like to use?")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    ForEach(detectedDates, id: \.self) { date in
                        Button(action: {
                            selectedDate = date
                        }) {
                            HStack {
                                Image(systemName: selectedDate == date ? "largecircle.fill.circle" : "circle")
                                    .foregroundColor(selectedDate == date ? .accentColor : .secondary)
                                Text(dateFormatter.string(from: date))
                                    .font(.system(size: 14))
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                            .padding(8)
                            .background(Color(NSColor.textBackgroundColor).opacity(selectedDate == date ? 1.0 : 0.6))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.accentColor.opacity(selectedDate == date ? 1.0 : 0.0), lineWidth: 2)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            } else {
                TextField(datePlaceholder, text: $dateText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 14))
                    .padding(12)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.accentColor.opacity(focusedField == .date ? 1.0 : 0.0), lineWidth: 2)
                    )
                    .focused($focusedField, equals: .date)
                    .onSubmit {
                        onComplete((title: titleText, dateText: dateText, selectedDate: nil, url: urlText))
                    }
            }
                
            TextField("URL (Optional)", text: $urlText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 14))
                .padding(12)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor.opacity(focusedField == .url ? 1.0 : 0.0), lineWidth: 2)
                )
                .focused($focusedField, equals: .url)
                .onSubmit {
                    onComplete((title: titleText, dateText: dateText, selectedDate: selectedDate, url: urlText))
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
                    onComplete((title: titleText, dateText: dateText, selectedDate: selectedDate, url: urlText))
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
                .disabled(detectedDates.count > 1 && selectedDate == nil)
                .opacity(detectedDates.count > 1 && selectedDate == nil ? 0.5 : 1.0)
            }
        }
        .padding(24)
        .frame(width: 600)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
        .cornerRadius(12)
    }
}


