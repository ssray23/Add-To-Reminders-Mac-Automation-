import Foundation

struct ParsedReminderData {
    let title: String
    let date: Date?
    let url: URL?
}

class TextParser {
    static func extractRelativeDate(from text: String) -> Date? {
        let pattern = "(?i)\\b(?:in\\s+)?(\\d+)\\s*(m|min|mins|minute|minutes|h|hr|hrs|hour|hours|d|day|days)\\b(?:\\s+from\\s+now)?"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        if let match = regex.firstMatch(in: text, options: [], range: nsRange) {
            if let valueRange = Range(match.range(at: 1), in: text),
               let unitRange = Range(match.range(at: 2), in: text),
               let value = Int(text[valueRange]) {
                
                let unitString = String(text[unitRange]).lowercased()
                var component = DateComponents()
                
                switch unitString {
                case "m", "min", "mins", "minute", "minutes":
                    component.minute = value
                case "h", "hr", "hrs", "hour", "hours":
                    component.hour = value
                case "d", "day", "days":
                    component.day = value
                default:
                    break
                }
                
                return Calendar.current.date(byAdding: component, to: Date())
            }
        }
        return nil
    }

    static func parse(text: String) -> ParsedReminderData {
        var extractedDate: Date? = nil
        var extractedURL: URL? = nil
        
        // Pre-process specifically for the date detector to handle common typos
        var textForParsing = text
        let typoFixes = [
            "tommorow": "tomorrow",
            "tomorow": "tomorrow",
            "tmrw": "tomorrow",
            "tmw": "tomorrow",
            "tonite": "tonight",
            "minuts": "minutes",
            "minut": "minute",
            "mintes": "minutes",
            "minits": "minutes",
            "hurs": "hours",
            "huors": "hours",
            "hores": "hours",
            "houra": "hours",
            "hra": "hrs"
        ]
        
        for (typo, fix) in typoFixes {
            textForParsing = textForParsing.replacingOccurrences(of: "\\b\(typo)\\b", with: fix, options: [.regularExpression, .caseInsensitive])
        }
        
        extractedDate = extractRelativeDate(from: textForParsing)
        
        let types: NSTextCheckingResult.CheckingType = [.date, .link]
        if let detector = try? NSDataDetector(types: types.rawValue) {
            let matches = detector.matches(in: textForParsing, options: [], range: NSRange(location: 0, length: textForParsing.utf16.count))
            
            for match in matches {
                if match.resultType == .date, extractedDate == nil {
                    extractedDate = match.date
                    
                    if let range = Range(match.range, in: textForParsing) {
                        let matchedText = String(textForParsing[range]).lowercased()
                        
                        if let date = extractedDate {
                            var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
                            
                            // NSDataDetector defaults to 12:00 PM (noon) if no time is provided.
                            if components.hour == 12 && components.minute == 0 && components.second == 0 {
                                // Ensure the user didn't actually type "12" or "noon"
                                if !matchedText.contains("12") && !matchedText.contains("noon") {
                                    components.hour = 7
                                    extractedDate = Calendar.current.date(from: components)
                                }
                            }
                        }
                    }
                } else if match.resultType == .link, extractedURL == nil {
                    extractedURL = match.url
                }
            }
        }
        
        // Sanitize the original text to be the title (keep dates and URLs in the title)
        let components = text.components(separatedBy: .whitespacesAndNewlines)
        var finalTitle = components.filter { !$0.isEmpty }.joined(separator: " ")
        
        // Remove leading punctuation like commas or dashes if they are somehow present,
        // though trimming whitespaces above is usually enough. 
        if finalTitle.isEmpty {
            finalTitle = "New Reminder"
        }
        
        return ParsedReminderData(title: finalTitle, date: extractedDate, url: extractedURL)
    }
}
