import Cocoa
import SwiftUI

class QuickEntryPanel: NSPanel {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
}

class QuickEntryWindowController: NSWindowController, NSWindowDelegate {
    static let shared = QuickEntryWindowController()
    
    private var completion: ((String?) -> Void)?
    
    init() {
        let rect = NSRect(x: 0, y: 0, width: 600, height: 160)
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
    
    func show(prompt: String, placeholder: String, initialText: String = "", completion: @escaping (String?) -> Void) {
        self.completion = completion
        
        NSApp.setActivationPolicy(.regular)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        
        self.window?.makeKeyAndOrderFront(nil)
        
        let view = QuickEntryView(prompt: prompt, placeholder: placeholder, text: initialText) { [weak self] result in
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

struct QuickEntryView: View {
    let prompt: String
    let placeholder: String
    @State var text: String
    let onComplete: (String?) -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(prompt)
                .font(.headline)
                .foregroundColor(.primary)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 18))
                .padding(12)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor.opacity(isFocused ? 1.0 : 0.0), lineWidth: 2)
                )
                .focused($isFocused)
                .onSubmit {
                    onComplete(text)
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isFocused = true
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
                    onComplete(text)
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
            }
        }
        .padding(24)
        .frame(width: 600)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
        .cornerRadius(12)
    }
}


