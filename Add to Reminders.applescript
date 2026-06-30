-- ==============================================================================
-- ADD TO REMINDERS (Automator Quick Action)
-- ==============================================================================
-- 
-- IMPORTANT: Saving and Reopening
-- 1. Automator saves Quick Actions to a hidden folder: ~/Library/Services/
-- 2. Use File > Save (Cmd + S) to apply changes directly to your system.
-- 3. Use File > Export ONLY when you want to backup or share the .workflow file.
-- 4. To reopen this file later, use File > Open Recent in Automator, or go to 
--    File > Open and press Cmd+Shift+G to search for ~/Library/Services/
-- 
-- ==============================================================================
on run {input, parameters}
	try
		set theText to ""
		try
			set theText to item 1 of input as text
		on error
			try
				set theText to input as text
			end try
		end try
		
		if theText is "" then
			display dialog "No text was received. Make sure text is selected before running this." buttons {"OK"}
			return input
		end if
		
		-- Clean up selected text: trim whitespace, collapse newlines
		set theText to do shell script "echo " & quoted form of theText & " | tr '\\n' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/[[:space:]]\\{2,\\}/ /g'"

		set theTitle to text returned of (display dialog "Enter a title for your reminder:" default answer theText buttons {"Cancel", "Create"} default button "Create" with icon note)
		
		set todayDate to do shell script "date '+%Y-%m-%d'"
		set apiKey to do shell script "security find-generic-password -a $USER -s anthropic_api_key -w"
		set jsonPrompt to "Today's date is " & todayDate & ". Extract the date and time mentioned in this text. Resolve relative references like 'tomorrow', 'next week', etc. relative to today. Reply with ONLY in format YYYY-MM-DD HH:MM (24-hour). If a specific time is mentioned, use it. If no time is mentioned or can be reasoned, default to 07:00. If no date is found at all, reply with NONE. Text: " & theText
		
		do shell script "python3 -c \"import json,sys; print(json.dumps(sys.argv[1]))\" " & quoted form of jsonPrompt & " > /tmp/claude_prompt.json"
		
		do shell script "curl -s https://api.anthropic.com/v1/messages -H 'x-api-key: " & apiKey & "' -H 'anthropic-version: 2023-06-01' -H 'content-type: application/json' -d '{\"model\":\"claude-sonnet-4-6\",\"max_tokens\":100,\"messages\":[{\"role\":\"user\",\"content\":'\"$(cat /tmp/claude_prompt.json)\"'}]}' > /tmp/claude_response.json"
		
		set dateString to do shell script "python3 -c \"import json,re; t=json.load(open('/tmp/claude_response.json'))['content'][0]['text'].strip(); m=re.search(r'\\\\d{4}-\\\\d{2}-\\\\d{2} \\\\d{2}:\\\\d{2}',t); print(m.group() if m else 'NONE')\""
		
		-- Extract URL from selected text if present
		set theURL to do shell script "echo " & quoted form of theText & " | grep -oE 'https?://[^ ]+' | head -1 || true"
		
		set theDate to missing value
		if dateString is not "NONE" then
			try
				set dateTimeParts to my splitText(dateString, " ")
				set datePart to item 1 of dateTimeParts
				set timePart to item 2 of dateTimeParts
				set dateParts to my splitText(datePart, "-")
				set timeParts to my splitText(timePart, ":")
				
				set theDate to current date
				set time of theDate to 0
				set day of theDate to 1
				set year of theDate to (item 1 of dateParts) as integer
				set month of theDate to (item 2 of dateParts) as integer
				set day of theDate to (item 3 of dateParts) as integer
				set hours of theDate to (item 1 of timeParts) as integer
				set minutes of theDate to (item 2 of timeParts) as integer
			on error
				try
					set dateInput to text returned of (display dialog "AI found '" & dateString & "' but couldn't parse it. Enter manually:" default answer dateString)
					set dateString to my parseDateWithAI(dateInput, todayDate, apiKey)
					if dateString is not "NONE" then
						set theDate to my parseDateString(dateString)
					end if
				end try
			end try
		else
			set tomorrowDate to do shell script "date -v+1d '+%d/%m/%Y 7:00 AM'"
			try
				set dateResult to display dialog "No date found in text. Enter a due date:" default answer tomorrowDate buttons {"No Date", "Cancel", "Set Date"} default button "Set Date" with icon note
				if button returned of dateResult is "Set Date" then
					set manualInput to text returned of dateResult
					-- Try AppleScript parsing first, fall back to AI
					try
						set theDate to date manualInput
						if (year of theDate) < 2000 then error "Bad year" -- Force AI fallback for weird parsing like '2'
						
						-- Only override time if native parsing succeeded and user didn't provide time
						if manualInput does not contain ":" then
							set hours of theDate to 7
							set minutes of theDate to 0
						end if
					on error
						try
							set dateString to my parseDateWithAI(manualInput, todayDate, apiKey)
							if dateString is not "NONE" then
								set theDate to my parseDateString(dateString)
							end if
						on error aiErr
							display dialog "Couldn't parse date: " & aiErr buttons {"OK"} with icon caution
						end try
					end try
				end if
			end try
		end if
		
		-- Build reminder properties
		if theURL is not "" then
			if theDate is not missing value then
				tell application "Reminders" to make new reminder with properties {name:theTitle, body:theURL, due date:theDate}
			else
				tell application "Reminders" to make new reminder with properties {name:theTitle, body:theURL}
			end if
		else
			if theDate is not missing value then
				tell application "Reminders" to make new reminder with properties {name:theTitle, due date:theDate}
			else
				tell application "Reminders" to make new reminder with properties {name:theTitle}
			end if
		end if
		
		-- Show confirmation with friendly date format
		if theDate is not missing value then
			-- Determine relative day
			set todayStr to short date string of (current date)
			set tomorrowStr to short date string of ((current date) + 1 * days)
			set reminderDateStr to short date string of theDate
			
			if reminderDateStr = todayStr then
				set dayLabel to "Today"
			else if reminderDateStr = tomorrowStr then
				set dayLabel to "Tomorrow"
			else
				set dayLabel to reminderDateStr
			end if
			
			-- Format time as 12-hour
			set h to hours of theDate
			set m to text -2 thru -1 of ("0" & (minutes of theDate))
			if h > 12 then
				set friendlyTime to (h - 12) & ":" & m & " PM"
			else if h = 12 then
				set friendlyTime to "12:" & m & " PM"
			else if h = 0 then
				set friendlyTime to "12:" & m & " AM"
			else
				set friendlyTime to h & ":" & m & " AM"
			end if
			
			display notification dayLabel & ", " & friendlyTime with title theTitle
		else
			display notification "No due date" with title theTitle
		end if
		
		-- Clean up temp files
		do shell script "rm -f /tmp/claude_prompt.json /tmp/claude_response.json"
		return input
		
	on error errMsg number errNum
		if errNum is not -128 then
			display dialog "Error " & errNum & ": " & errMsg buttons {"OK"} with icon stop
		end if
		return input
	end try
end run

on splitText(theText, theDelimiter)
	set oldDelims to AppleScript's text item delimiters
	set AppleScript's text item delimiters to theDelimiter
	set theItems to text items of theText
	set AppleScript's text item delimiters to oldDelims
	return theItems
end splitText

on parseDateWithAI(inputText, todayDate, apiKey)
	set parsePrompt to "Today's date is " & todayDate & ". Convert this to a date and time: '" & inputText & "'. Reply with ONLY YYYY-MM-DD HH:MM (24-hour). If no time mentioned, use 07:00. If you cannot determine a date, reply NONE."
	do shell script "python3 -c \"import json,sys; print(json.dumps(sys.argv[1]))\" " & quoted form of parsePrompt & " > /tmp/claude_prompt.json"
	do shell script "curl -s https://api.anthropic.com/v1/messages -H 'x-api-key: " & apiKey & "' -H 'anthropic-version: 2023-06-01' -H 'content-type: application/json' -d '{\"model\":\"claude-sonnet-4-6\",\"max_tokens\":100,\"messages\":[{\"role\":\"user\",\"content\":'\"$(cat /tmp/claude_prompt.json)\"'}]}' > /tmp/claude_response.json"
	return do shell script "python3 -c \"import json,re; t=json.load(open('/tmp/claude_response.json'))['content'][0]['text'].strip(); m=re.search(r'\\\\d{4}-\\\\d{2}-\\\\d{2} \\\\d{2}:\\\\d{2}',t); print(m.group() if m else 'NONE')\""
end parseDateWithAI

on parseDateString(dateString)
	set dateTimeParts to my splitText(dateString, " ")
	set datePart to item 1 of dateTimeParts
	set timePart to item 2 of dateTimeParts
	set dateParts to my splitText(datePart, "-")
	set timeParts to my splitText(timePart, ":")
	
	set theDate to current date
	set time of theDate to 0
	set day of theDate to 1
	set year of theDate to (item 1 of dateParts) as integer
	set month of theDate to (item 2 of dateParts) as integer
	set day of theDate to (item 3 of dateParts) as integer
	set hours of theDate to (item 1 of timeParts) as integer
	set minutes of theDate to (item 2 of timeParts) as integer
	return theDate
end parseDateString