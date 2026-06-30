# Add to Reminders (Mac Quick Action)

A macOS Automator Quick Action that allows you to seamlessly add selected text from anywhere on your Mac directly into your Apple Reminders app. 

It uses AI (Claude by Anthropic) to extract and understand natural language dates hidden within your text, parsing them to properly schedule your reminders.

## Features

- **Global Quick Action**: Accessible by simply right-clicking selected text in Safari, Mail, Notes, or any native macOS app.
- **Smart Date Extraction**: Uses Claude AI to read the text and pull out phrases like "tomorrow afternoon", "next week", or "11th July 2 pm" and sets the reminder due date accordingly.
- **URL Extraction**: Automatically extracts the first web link found in your selection and adds it to the Notes section of the created Reminder, making it clickable.
- **AI Fallbacks**: If no date is found, you are prompted to enter one manually. If AppleScript fails to parse your manual entry, it relies on the AI to parse exactly what you meant.
- **Auto-Formatting**: Trims junk whitespace and strange newlines from text grabbed from emails and web pages.

## How It Works

1. **Text Extraction**: The Automator workflow receives your selected text.
2. **Title Prompt**: You are prompted to adjust the title of the reminder.
3. **AI Parsing**: The script calls the Anthropic API (using your securely stored API key) and asks Claude to analyze the text. Claude extracts the date and resolves relative references (e.g., "tomorrow") against today's date.
4. **URL Matching**: The script runs a regex to locate `http` or `https` links.
5. **Creation**: It uses AppleScript's native `Reminders` integration to quietly generate the reminder in the background with the correct due date and URL attachment.

## Setup Requirements

1. An Anthropic API Key.
2. The API key must be securely saved to your Mac's Keychain using the name `anthropic_api_key`. To save your key, run this command in your Terminal:
   ```bash
   security add-generic-password -a $USER -s anthropic_api_key -w "YOUR_KEY_HERE"
   ```

## Editing the Script

Quick Actions are saved in a hidden system folder, so you cannot browse to them normally in Finder. 

**To Reopen the Script in Automator:**
1. Open Automator.
2. Go to **File > Open Recent** to quickly access it.
3. If it's not in the Recent menu, press **Cmd + O**, then press **Cmd + Shift + G** and paste the hidden folder path: `~/Library/Services/`
4. Select the `.workflow` file.

**Saving vs Exporting:**
- **Save (Cmd + S)**: Automatically updates the live quick action on your system. Always use this to apply your edits.
- **Export**: Packages the workflow into an installer file. Use this ONLY if you want to back it up somewhere (like an external drive or GitHub) or send it to a friend.
