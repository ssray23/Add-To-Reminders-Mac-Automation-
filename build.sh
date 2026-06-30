#!/bin/bash
set -e

APP_NAME="AddToReminders"
APP_DIR="$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"

# Create directories
mkdir -p "$MACOS_DIR"
mkdir -p "$APP_DIR/Contents/Resources"

# Compile Swift files
echo "Compiling Swift files..."
swiftc source/*.swift -o "$MACOS_DIR/$APP_NAME" -target arm64-apple-macosx11.0

# Copy Reminders icon
echo "Copying App Icon..."
cp /System/Applications/Reminders.app/Contents/Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"

# Copy Info.plist
echo "Copying Info.plist..."
cp Info.plist "$APP_DIR/Contents/Info.plist"

# Sign the app
echo "Code signing..."
xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"

# Notify Services system of new service
echo "Updating dynamic services..."
/System/Library/CoreServices/pbs -flush

echo "Build complete. App is at $APP_DIR"
