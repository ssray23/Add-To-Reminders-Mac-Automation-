# Add to Reminders (Swift)

A lightning-fast, native macOS Quick Action that allows you to highlight text anywhere on your Mac and instantly turn it into an Apple Reminder. 

Built entirely in Swift natively, it replaces cloud-based AI parsing with Apple's on-device frameworks for instantaneous results, complete privacy, and zero API costs.

## Features
- **Relative & Absolute Date Parsing:** Supports relative times like "in 3 hours", "30 mins from now", "in 2 weeks", "in 6 months from now", or "in 1 year" via custom regex, and falls back to Apple's incredibly fast `NSDataDetector` for absolute dates.
- **Recurrence Rules:** Natural language parsing for repeating events! Just type "repeat daily", "weekly", "every month", or "yearly" and the reminder will automatically be configured to recur.
- **Smart Fallbacks:** Handles common typos (e.g., "tommorow", "minuts"), spelled-out ordinals (e.g. "Fourth of July" -> "4th of July"), and gracefully defaults to 7:00 AM for dates without specific times. It also includes specific workarounds for Apple's `NSDataDetector` quirks, such as preventing the word "due" from incorrectly snapping reminder dates to "today".
- **Clean Titles:** Automatically strips out empty parentheses, dangling prepositions (e.g. "Expires"), and trailing punctuation left behind after date extraction to ensure pristine reminder titles.
- **Global Quick Entry:** Hit `Cmd + R` from anywhere on your Mac to summon a floating Quick Entry UI. Type in a reminder with natural language (e.g. "Buy milk tomorrow at 5pm") and press Enter to instantly add it.
- **Interactive Prompts:** If no date is found in highlighted text, it prompts you via a native `NSAlert` dialog asking "When to remind you?" with a smart default (Tomorrow at 7am) and options for "No Date", "Set Date", or "Cancel".
- **Instant Visual Feedback:** Displays a sleek, non-blocking SwiftUI HUD animation the moment you trigger the action.
- **Native Notifications:** Triggers a standard macOS Notification Center alert (featuring the official Apple Reminders icon) displaying the parsed due date and time in a beautiful, human-readable format (e.g., `12th July 2026, 9:00 am` or `Tomorrow, 7:00 am`).
- **URL Extraction:** Automatically extracts the first URL found in your selected text and adds it to the reminder's metadata.
- **Persistent Background Agent:** Runs completely in the background as an `LSUIElement` app. It stays alive after the first launch to ensure subsequent reminders are instantaneous, to listen for global hotkeys, and to seamlessly manage macOS TCC (Permissions) without constant re-prompting.

## Architecture & How the Code Works
The project operates as a headless macOS Background Service that listens for Pasteboard events. 

- **`AppDelegate.swift` / `main.swift`:** The entry points of the application. They configure the app as a background agent and register `ServiceProvider` to handle incoming text from the macOS Pasteboard.
- **`ServiceProvider.swift`:** The core controller. Receives the highlighted text, calls the parser, and orchestrates the creation of the reminder. It handles the `NSAlert` prompt fallback when no date is extracted natively.
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

## How to Port to Another Mac
To install this on another Mac, you do not need to install Xcode. You only need the standard command line tools.
1. Copy this entire project folder to the new Mac.
2. Open Terminal on the new Mac and navigate to the folder.
3. Run `./build.sh`.
4. macOS will automatically register the newly compiled `AddToReminders.app` as a Service tailored to that machine's architecture. 
5. Enable it in **System Settings > Keyboard > Keyboard Shortcuts > Services** as described above.
