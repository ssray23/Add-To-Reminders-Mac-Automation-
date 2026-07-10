import Cocoa
import Carbon
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    let serviceProvider = ServiceProvider()
    var hotKeyRef: EventHotKeyRef?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApp.servicesProvider = serviceProvider
        NSUpdateDynamicServices()
        
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .notRegistered {
                    try SMAppService.mainApp.register()
                    print("Successfully registered for login")
                }
            } catch {
                print("Failed to register for login: \(error)")
            }
        }
        
        registerGlobalHotKey()
    }
    
    func registerGlobalHotKey() {
        var hotKeyId = EventHotKeyID()
        hotKeyId.signature = OSType(fourCharCode("HOTK"))
        hotKeyId.id = 1
        
        // Command + R
        let modifierFlags = UInt32(cmdKey)
        let keyCode = UInt32(kVK_ANSI_R)
        
        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = OSType(kEventHotKeyPressed)
        
        let appTarget = GetApplicationEventTarget()
        
        // Install handler
        let handlerStatus = InstallEventHandler(appTarget, { (nextHandler, theEvent, userData) -> OSStatus in
            NotificationCenter.default.post(name: NSNotification.Name("QuickEntryHotKeyPressed"), object: nil)
            return noErr
        }, 1, &eventType, nil, nil)
        
        print("InstallEventHandler status: \(handlerStatus)")
        
        // Register hotkey
        let registerStatus = RegisterEventHotKey(keyCode, modifierFlags, hotKeyId, appTarget, 0, &hotKeyRef)
        print("RegisterEventHotKey status: \(registerStatus)")
        
        // Listen for the notification to trigger our Quick Entry UI
        NotificationCenter.default.addObserver(self, selector: #selector(handleHotKey), name: NSNotification.Name("QuickEntryHotKeyPressed"), object: nil)
    }
    
    @objc func handleHotKey() {
        serviceProvider.showQuickEntry()
    }
    
    private func fourCharCode(_ string: String) -> Int {
        var result: Int = 0
        for char in string.utf16 {
            result = (result << 8) + Int(char)
        }
        return result
    }
}
