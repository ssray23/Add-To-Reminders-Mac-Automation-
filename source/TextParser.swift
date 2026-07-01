import Foundation
import EventKit

struct ParsedReminderData {
    let title: String
    let date: Date?
    let url: URL?
    let recurrence: EKRecurrenceRule?
}

class TextParser {
    static func extractRecurrence(text: inout String) -> EKRecurrenceRule? {
        let patterns: [(regex: String, frequency: EKRecurrenceFrequency)] = [
            ("(?i)\\b(every\\s*day|daily|repeat\\s*daily)\\b", .daily),
            ("(?i)\\b(every\\s*week|weekly|repeat\\s*weekly)\\b", .weekly),
            ("(?i)\\b(every\\s*month|monthly|repeat\\s*monthly)\\b", .monthly),
            ("(?i)\\b(every\\s*year|yearly|repeat\\s*yearly)\\b", .yearly)
        ]
        
        for item in patterns {
            if let regex = try? NSRegularExpression(pattern: item.regex, options: []) {
                let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
                if let match = regex.firstMatch(in: text, options: [], range: nsRange) {
                    if let range = Range(match.range, in: text) {
                        text.removeSubrange(range)
                    }
                    return EKRecurrenceRule(recurrenceWith: item.frequency, interval: 1, end: nil)
                }
            }
        }
        return nil
    }

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
        
        var cleanOriginalText = text
        let recurrenceRule = extractRecurrence(text: &cleanOriginalText)
        
        // Pre-process specifically for the date detector to handle common typos
        var textForParsing = cleanOriginalText
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
        
        let ordinalFixes = [
            "first": "1st", "second": "2nd", "third": "3rd", "fourth": "4th", "fifth": "5th",
            "sixth": "6th", "seventh": "7th", "eighth": "8th", "ninth": "9th", "tenth": "10th",
            "eleventh": "11th", "twelfth": "12th", "thirteenth": "13th", "fourteenth": "14th",
            "fifteenth": "15th", "sixteenth": "16th", "seventeenth": "17th", "eighteenth": "18th",
            "nineteenth": "19th", "twentieth": "20th", "twenty-first": "21st", "twenty-second": "22nd",
            "twenty-third": "23rd", "twenty-fourth": "24th", "twenty-fifth": "25th", "twenty-sixth": "26th",
            "twenty-seventh": "27th", "twenty-eighth": "28th", "twenty-ninth": "29th", "thirtieth": "30th",
            "thirty-first": "31st"
        ]
        
        for (typo, fix) in typoFixes {
            textForParsing = textForParsing.replacingOccurrences(of: "\\b\(typo)\\b", with: fix, options: [.regularExpression, .caseInsensitive])
        }
        
        for (word, number) in ordinalFixes {
            textForParsing = textForParsing.replacingOccurrences(of: "\\b\(word)\\b", with: number, options: [.regularExpression, .caseInsensitive])
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
                                // Ensure the user didn't actually type "12" as a time
                                let timeIndicatorRegex = "(?i)(\\b12\\s*(pm|p\\.m\\.|am|a\\.m\\.)\\b|\\b12:00\\b|\\bnoon\\b|\\bat\\s+12\\b)"
                                let explicitlyMentioned12 = matchedText.range(of: timeIndicatorRegex, options: .regularExpression) != nil
                                
                                if !explicitlyMentioned12 {
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
        let components = cleanOriginalText.components(separatedBy: .whitespacesAndNewlines)
        var finalTitle = components.filter { !$0.isEmpty }.joined(separator: " ")
        
        // Remove leading punctuation like commas or dashes if they are somehow present,
        // though trimming whitespaces above is usually enough. 
        if finalTitle.isEmpty {
            finalTitle = "New Reminder"
        }
        
        return ParsedReminderData(title: finalTitle, date: extractedDate, url: extractedURL, recurrence: recurrenceRule)
    }
}
