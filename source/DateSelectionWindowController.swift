import Cocoa
import SwiftUI

class DateSelectionWindowController: NSWindowController, NSWindowDelegate {
    static let shared = DateSelectionWindowController()
    
    private var completion: ((Date?) -> Void)?
    
    init() {
        let rect = NSRect(x: 0, y: 0, width: 600, height: 300)
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
    
    func show(dates: [Date], completion: @escaping (Date?) -> Void) {
        self.completion = completion
        
        NSApp.setActivationPolicy(.regular)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        
        self.window?.makeKeyAndOrderFront(nil)
        
        let view = DateSelectionView(dates: dates) { [weak self] result in
            self?.closeWindow()
            completion(result)
        }
        
        self.window?.contentView = NSHostingView(rootView: view)
    }
    
    private func closeWindow() {
        self.window?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        closeWindow()
        completion?(nil)
        return true
    }
}

struct DateSelectionView: View {
    let dates: [Date]
    let onComplete: ((Date?) -> Void)
    
    @State private var selectedDate: Date?
    
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Multiple dates detected. Which one would you like to use?")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 10) {
                ForEach(dates, id: \.self) { date in
                    Button(action: {
                        selectedDate = date
                    }) {
                        HStack {
                            Image(systemName: selectedDate == date ? "largecircle.fill.circle" : "circle")
                                .foregroundColor(selectedDate == date ? .accentColor : .secondary)
                            Text(dateFormatter.string(from: date))
                                .font(.system(size: 16))
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        .padding(12)
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
            .padding(.vertical, 8)
            
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
                    onComplete(selectedDate)
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
                .disabled(selectedDate == nil)
                .opacity(selectedDate == nil ? 0.5 : 1.0)
            }
        }
        .padding(24)
        .frame(width: 600)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
        .cornerRadius(12)
        .onAppear {
            if let first = dates.first {
                selectedDate = first
            }
        }
    }
}
