set todayDate to do shell script "date '+%Y-%m-%d'"
set apiKey to do shell script "security find-generic-password -a $USER -s anthropic_api_key -w"
set parsePrompt to "Today's date is " & todayDate & ". Convert this to a date and time: '11th july 2 pm'. Reply with ONLY YYYY-MM-DD HH:MM (24-hour). If no time mentioned, use 07:00. If you cannot determine a date, reply NONE."
do shell script "python3 -c \"import json,sys; print(json.dumps(sys.argv[1]))\" " & quoted form of parsePrompt & " > /tmp/claude_prompt.json"
do shell script "curl -s https://api.anthropic.com/v1/messages -H 'x-api-key: " & apiKey & "' -H 'anthropic-version: 2023-06-01' -H 'content-type: application/json' -d '{\"model\":\"claude-sonnet-4-6\",\"max_tokens\":30,\"messages\":[{\"role\":\"user\",\"content\":'\"$(cat /tmp/claude_prompt.json)\"'}]}' > /tmp/claude_response.json"
set dateString to do shell script "python3 -c \"import json,re; t=json.load(open('/tmp/claude_response.json'))['content'][0]['text'].strip(); m=re.search(r'\\\\d{4}-\\\\d{2}-\\\\d{2} \\\\d{2}:\\\\d{2}',t); print(m.group() if m else 'NONE')\""
return dateString
