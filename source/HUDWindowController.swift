import Cocoa
import SwiftUI

enum HUDState {
    case processing
    case success(ParsedReminderData)
    case error(String)
}

class HUDWindowController {
    static let shared = HUDWindowController()
    var window: NSWindow?
    
    func show(state: HUDState) {
        if window == nil {
            let rect = NSRect(x: 0, y: 0, width: 300, height: 120)
            let win = NSWindow(contentRect: rect,
                               styleMask: [.borderless],
                               backing: .buffered,
                               defer: false)
            win.level = .floating
            win.backgroundColor = .clear
            win.isOpaque = false
            win.hasShadow = true
            win.center()
            self.window = win
        }
        
        let view = AnimationView(state: state)
        window?.contentView = NSHostingView(rootView: view)
        window?.makeKeyAndOrderFront(nil)
        
        // Auto-hide on success or error
        switch state {
        case .success, .error:
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                self.hide()
            }
        default:
            break
        }
    }
    
    func hide() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.5
            window?.animator().alphaValue = 0
        }, completionHandler: {
            self.window?.orderOut(nil)
            self.window?.alphaValue = 1.0
        })
    }
}
