# Add to Reminders (Swift)

A lightning-fast, native macOS Quick Action that allows you to highlight text anywhere on your Mac and instantly turn it into an Apple Reminder. 

Built entirely in Swift natively, it replaces cloud-based AI parsing with Apple's on-device frameworks for instantaneous results, complete privacy, and zero API costs.

## Features
- **Relative & Absolute Date Parsing:** Supports relative times explicitly marked with keywords like "in 3 hours", "30 mins from now", "in 2 weeks", "in 6 months from now", or "in 1 year" via custom regex, and seamlessly uses Apple's incredibly fast `NSDataDetector` for absolute dates.
- **Multiple Date Selection:** If multiple potential dates are detected in your highlighted text, a sleek interactive popup appears to let you select precisely which date you want to use for the reminder.
- **Multi-line Date & Time Merging:** Intelligently combines separate date and time components (e.g., a date on one line and a time on the next) into a single cohesive reminder time, avoiding partial extraction issues.
- **Recurrence Rules:** Natural language parsing for repeating events! Supports complex patterns like "every 3 days", "every other week", "repeat daily", "weekly", "every month", or "yearly". You can even specify an end date by appending "until [date]" or "ending on [date]".
- **Smart Fallbacks:** Handles common typos (e.g., "tommorow", "minuts") specifically for the date/time engine while intentionally preserving your exact phrasing and brand names in the actual reminder title. It also parses spelled-out ordinals (e.g. "Fourth of July" -> "4th of July"), and gracefully defaults to 7:00 AM for dates without specific times. It perfectly mitigates `NSDataDetector` bugs that misinterpret words like "due", "before", "by", or "until" as durations starting from today.
- **Clean Titles:** Automatically strips out empty parentheses, dangling prepositions (e.g. "Expires"), and trailing punctuation left behind after date extraction to ensure pristine reminder titles.
- **Global Quick Entry:** Hit `Cmd + R` from anywhere on your Mac to summon a floating, borderless Quick Entry window powered by SwiftUI. Type in a reminder with natural language (e.g. "Buy milk tomorrow at 5pm") and press Enter to instantly add it.
- **Interactive Prompts:** If no date is found in highlighted text, a native translucent window smoothly prompts you asking "When to remind you?" with a smart default (Tomorrow at 7am) and options for "No Date", "Set Date", or "Cancel".
- **Instant Visual Feedback:** Displays a sleek, non-blocking SwiftUI HUD animation the moment you trigger the action.
- **Native Notifications:** Triggers a standard macOS Notification Center alert (featuring the official Apple Reminders icon) displaying the parsed due date and time in a beautiful, human-readable format (e.g., `12th July 2026, 9:00 am` or `Tomorrow, 7:00 am`).
- **URL Extraction & Input:** Automatically extracts the first URL found in your selected text. You can also manually paste URLs into a dedicated URL field in the Quick Entry window. Due to a known macOS EventKit bug where the UI ignores third-party API URLs, the app intelligently falls back to injecting the URL directly into the Reminder's Notes field so it remains instantly clickable.
- **Persistent Background Agent:** Runs completely in the background as an `LSUIElement` app. It stays alive after the first launch to ensure subsequent reminders are instantaneous, to listen for global hotkeys, and to seamlessly manage macOS TCC (Permissions) without constant re-prompting.

## Architecture & How the Code Works
The project operates as a headless macOS Background Service that listens for Pasteboard events. 

- **`AppDelegate.swift` / `main.swift`:** The entry points of the application. They configure the app as a background agent and register `ServiceProvider` to handle incoming text from the macOS Pasteboard.
- **`ServiceProvider.swift`:** The core controller. Receives the highlighted text, calls the parser, and orchestrates the creation of the reminder. It coordinates with `QuickEntryWindowController` for interactive prompts.
- **`QuickEntryWindowController.swift`:** Provides a native, borderless SwiftUI floating window for manual text entry and date prompts, avoiding the blocking event loops of standard `NSAlert` modals.
- **`TextParser.swift`:** Pre-processes the text to fix common typos, then uses `NSDataDetector` to extract dates and URLs. It intercepts the default `12:00 PM` time and enforces the `7:00 AM` default time rule.
- **`RemindersManager.swift`:** Uses `EventKit` (`EKEventStore`) to safely request authorization and save the reminder directly to your default Reminders list.
- **`HUDWindowController.swift` & `AnimationView.swift`:** Handles the immediate visual feedback via a borderless, transparent `NSWindow` hosting a SwiftUI view.
- **`NotificationHelper.swift`:** Formats the final due date with ordinal suffixes and uses a background AppleScript (`osascript`) command to seamlessly trigger a native notification from the Reminders app.
- **`build.sh`:** A custom bash script that compiles the Swift files, structures the `.app` bundle, copies the `Info.plist`, bundles the official Reminders `AppIcon.icns`, strips extended attributes, applies an ad-hoc code signature, and dynamically updates the macOS Services registry (`/System/Library/CoreServices/pbs`).

## How to Build & Run
1. Open Terminal and navigate to this project directory.
2. Make the build script executable (if not already): 
   ```bash
   chmod +x build.sh
   ```
3. Run the build script: 
   ```bash
   ./build.sh
   ```
   *This automatically force-quits any old background instances, compiles the Swift code, builds `AddToReminders.app`, and registers it with macOS.*
4. Go to **System Settings > Keyboard > Keyboard Shortcuts > Services**.
5. Under "Text", ensure **Add to Reminders** is checked.
6. To use it, simply highlight text in any app (Safari, Notes, Mail, etc.), right-click, select **Services**, and click **Add to Reminders**. 
   - *Note: On the first run, macOS will ask for permission to access your Reminders. Because the app stays running in the background, it will remember this permission permanently.*

## How to Install on Another Mac
Because this app is self-contained, you do not need Xcode or the terminal to install it on another Mac.

1. Download or copy the pre-packaged **`AddToReminders_Install.zip`** to the new Mac.
2. Unzip it and drag the **`AddToReminders.app`** into your **Applications** folder.
3. **Right-Click** the app and select **"Open"**. 
   - *Note: You must Right-Click -> Open the very first time to bypass macOS Gatekeeper, as this app is not signed with a paid Apple Developer certificate.*
4. The app will launch silently in the background. macOS will scan it and automatically register the global service.
5. Enable the shortcut by going to **System Settings > Keyboard > Keyboard Shortcuts > Services** and ensuring **Add to Reminders** is checked.
