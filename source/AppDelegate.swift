import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    let serviceProvider = ServiceProvider()
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApp.servicesProvider = serviceProvider
        NSUpdateDynamicServices()
    }
}
