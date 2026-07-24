#!/bin/bash
set -e

REPO_DIR="$PWD"

# The built .app MUST live outside any cloud-synced folder (iCloud Drive, OneDrive, etc).
# macOS verifies the calling app's code signature by reading its binary off disk before
# granting certain requests (NSOpenPanel, FileManager.trashItem, etc). If that binary sits
# inside a live-synced folder, that read can stall indefinitely waiting on the sync daemon
# instead of returning instantly like it would from local disk. Building to ~/Applications
# keeps the source in iCloud Drive (fine, it's just text) while the runnable app itself
# is always local-only.
APP_OUTPUT_DIR="$HOME/Applications"
mkdir -p "$APP_OUTPUT_DIR"

APP_NAME="AddToReminders"
APP_DIR="$APP_OUTPUT_DIR/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"

# Force quit any existing instances so the new build can run immediately
echo "Stopping existing app instances..."
killall "$APP_NAME" 2>/dev/null || true

# Create directories
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$APP_DIR/Contents/Resources"

# Run regression tests
echo "Running automated regression tests..."
swiftc source/TextParser.swift tests/RegressionTests.swift -o /tmp/regression_test_runner
/tmp/regression_test_runner
rm -f /tmp/regression_test_runner

# Compile Swift files
echo "Compiling Swift files..."
swiftc source/*.swift -o "$MACOS_DIR/$APP_NAME" -target arm64-apple-macosx12.0

# Copy Reminders icon
echo "Copying App Icon..."
cp /System/Applications/Reminders.app/Contents/Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"

# Copy Info.plist
echo "Copying Info.plist..."
cp Info.plist "$APP_DIR/Contents/Info.plist"

# Touch the app bundle so Finder registers the changes
touch "$APP_DIR"

# Sign the app
echo "Code signing..."
xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"

# Notify Services system of new service
echo "Updating dynamic services..."
/System/Library/CoreServices/pbs -flush

echo "✅ Build complete! App installed to: $APP_DIR"
echo "   Run it with: open \"$APP_DIR\""

# Package into a deployable zip
echo "Packaging zip file..."
rm -f "$REPO_DIR/AddToReminders_Install.zip"
(cd "$APP_OUTPUT_DIR" && zip -q -r "$REPO_DIR/AddToReminders_Install.zip" "$APP_NAME.app")

echo "Done! You can share AddToReminders_Install.zip"
