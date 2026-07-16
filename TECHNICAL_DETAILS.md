# Technical Details & Architecture

This document is intended for developers and technical audiences who want to understand the inner workings of the **Add to Reminders** macOS service. 

The application is written natively in Swift and operates as an `LSUIElement` background application. It registers itself dynamically as a macOS text service, allowing users to invoke it from any application by highlighting text.

## File Breakdown

### 1. `main.swift` & `AppDelegate.swift`
- **`main.swift`**: The raw entry point of the application. It creates a barebones `NSApplication` instance, sets the `AppDelegate`, and starts the native macOS run loop.
- **`AppDelegate.swift`**: Implements the `NSApplicationDelegate`. Its primary role is to register the application as a macOS Service provider. It programmatically constructs a minimal main menu (including an Edit menu) to ensure standard macOS text editing keyboard shortcuts (like `Cmd+V`, `Cmd+C`) route correctly through the responder chain to the floating panels. It initializes the `ServiceProvider` class, assigns it to `NSApp.servicesProvider`, and calls `NSUpdateDynamicServices()` to flush the macOS services registry. Since the app runs as an `LSUIElement` (no dock icon), it stays persistently active in the background to handle subsequent requests instantly without cold-booting, and to seamlessly retain TCC (Privacy/Reminders) permissions.

### 2. `ServiceProvider.swift`
- **Role**: The core orchestrator and the responder for the macOS Services API.
- **Details**: It exposes an Objective-C accessible method `@objc func processText(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>)` which macOS invokes when the user triggers the service. It retrieves the highlighted string from the pasteboard, delegates parsing to `TextParser`, and manages control flow. If multiple dates are extracted, it presents a native floating window using `DateSelectionWindowController` to let the user select the desired date. If no date is extracted, it presents a native translucent window via `QuickEntryWindowController` to solicit a date/time from the user (with natural language support). Once a date is resolved, it triggers the HUD animation and invokes `RemindersManager` to save the reminder.

### 3. `QuickEntryWindowController.swift` & `DateSelectionWindowController.swift`
- **Role**: Provides native, borderless SwiftUI floating windows for manual text entry/date prompts and multiple date selection, avoiding the blocking event loops of standard `NSAlert` modals.

### 4. `TextParser.swift`
- **Role**: The natural language processing engine for dates, times, recurrence, and URLs.
- **Details**: Instead of relying on a cloud-based LLM or API, the parser uses a combination of custom Regular Expressions and Apple's incredibly fast `NSDataDetector`. 
  - **Recurrence Extraction**: First uses regex to identify and strip out recurrence keywords (e.g., "repeat daily", "every week") mapping them to `EKRecurrenceRule` objects.
  - **Typo & Ordinal Pre-processing**: Corrects common spelling mistakes (e.g., "tommorow") and maps spelled-out ordinals (e.g., "Fourth" -> "4th") so that `NSDataDetector` can interpret them successfully.
  - **Relative Parsing:** Evaluates phrases like "in 3 hours" or "in 2 years" manually via regex. It intelligently distinguishes between pure date offsets (days, weeks, months) and time offsets (hours, minutes) to allow accurate merging with explicit times later.
  - **Absolute Parsing & Intelligent Merging:** Passes the text to `NSDataDetector` to find dates and URLs. It features a robust merging strategy that sequentially resolves and combines all extracted `DateComponents` based on their original string positions. This ensures that relative dates can seamlessly merge with absolute times (e.g., parsing "in 3 days at 9 am" into a single event) and gracefully handles scenarios where date and time are provided on different lines. It overrides the default `12:00 PM` to `7:00 AM` if no explicit time was given. It also implements a clever zero-width space injection trick (`\u{200B}`) to prevent `NSDataDetector` bugs with words like "due".
  - **Final Title Polish**: After date and URL extraction, the parser runs a final regex cleanup pass to strip dangling prepositions (e.g. "expires", "due"), remove empty brackets/parentheses `()`, and trim any trailing punctuation (like colons or dashes) to ensure the final reminder title is clean.

### 5. `RemindersManager.swift`
- **Role**: Handles persistence and interactions with Apple's `EventKit` framework.
- **Details**: A singleton wrapper around `EKEventStore`. It asynchronously requests authorization to access Reminders (`EKEventStore.requestFullAccessToReminders`). Once granted, it constructs an `EKReminder` object, applies the parsed due date (`dueDateComponents`), attaches the recurrence rule (`EKRecurrenceRule`), sets an absolute alarm (`EKAlarm`) so a notification fires at the target time, and commits the reminder directly to the user's default Reminders list.

### 6. `HUDWindowController.swift`
- **Role**: Manages the transient, borderless heads-up display (HUD).
- **Details**: Inherits from `NSWindowController`. It configures a completely transparent, floating, non-activating `NSWindow` that is positioned dead center on the user's main screen. It hosts the SwiftUI `AnimationView` using an `NSHostingView`. It provides programmatic methods to transition the HUD between states (`.processing`, `.success`, `.error`) and manages an auto-dismissal timer to fade out the window after a few seconds.

### 7. `AnimationView.swift`
- **Role**: The visual layer for the HUD.
- **Details**: Built in SwiftUI. It observes the current state from the `HUDWindowController` and renders appropriate visuals. Uses fundamental SwiftUI animations (e.g., `withAnimation`, `rotationEffect`) to draw a spinning loader during processing, which seamlessly transitions into a checkmark upon success or a cross upon failure.

### 8. `NotificationHelper.swift`
- **Role**: Issues native macOS Notification Center alerts.
- **Details**: Before emitting a notification, it formats the successfully parsed `Date` into a highly human-readable string (e.g., "Tomorrow, 7:00 am" or "12th July 2026, 9:00 am") by dynamically calculating ordinal suffixes (st, nd, rd, th). Instead of using standard `UNUserNotificationCenter` (which would display the generic terminal/script icon), it utilizes a clever workaround: it spawns a `Process()` to execute a one-liner AppleScript (`osascript -e 'display notification ...'`) masquerading as the official Apple Reminders application. This ensures the notification carries the recognizable Reminders icon.

### 9. `build.sh` (Shell Script)
- **Role**: A streamlined build pipeline replacing Xcode's xcodeproj overhead.
- **Details**: First, it safely terminates any currently running instances of the app (`killall`) so new changes apply instantly. Then, it compiles the pure `.swift` files into a Mach-O arm64 binary using `swiftc`. It constructs the standard macOS application bundle structure (`AddToReminders.app/Contents/MacOS`), dynamically copies in the `Info.plist`, steals the official `AppIcon.icns` from the system Reminders app, ad-hoc signs the application using `codesign`, and importantly calls `/System/Library/CoreServices/pbs -flush` to immediately register the newly built service with the macOS Services architecture.
