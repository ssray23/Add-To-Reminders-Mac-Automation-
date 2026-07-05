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

    static func extractRelativeDate(text: inout String) -> Date? {
        let pattern = "(?i)\\b(?:in\\s+)?(\\d+(?:[.,]\\d+)?)\\s*(m|min|mins|minute|minutes|h|hr|hrs|hour|hours|d|day|days|w|wk|wks|week|weeks|mo|mos|month|months|y|yr|yrs|year|years)\\b(?:\\s+from\\s+now)?"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        if let match = regex.firstMatch(in: text, options: [], range: nsRange) {
            if let valueRange = Range(match.range(at: 1), in: text),
               let unitRange = Range(match.range(at: 2), in: text) {
                
                let valueString = String(text[valueRange]).replacingOccurrences(of: ",", with: ".")
                guard let value = Double(valueString) else { return nil }
                
                let unitString = String(text[unitRange]).lowercased()
                var component = DateComponents()
                
                switch unitString {
                case "m", "min", "mins", "minute", "minutes":
                    component.minute = Int(value)
                    component.second = Int(value.truncatingRemainder(dividingBy: 1) * 60)
                case "h", "hr", "hrs", "hour", "hours":
                    component.hour = Int(value)
                    component.minute = Int(value.truncatingRemainder(dividingBy: 1) * 60)
                case "d", "day", "days":
                    component.day = Int(value)
                    component.hour = Int(value.truncatingRemainder(dividingBy: 1) * 24)
                case "w", "wk", "wks", "week", "weeks":
                    component.day = Int(value) * 7
                    component.hour = Int(value.truncatingRemainder(dividingBy: 1) * 24 * 7)
                case "mo", "mos", "month", "months":
                    component.month = Int(value)
                    component.day = Int(value.truncatingRemainder(dividingBy: 1) * 30)
                case "y", "yr", "yrs", "year", "years":
                    component.year = Int(value)
                    component.month = Int(value.truncatingRemainder(dividingBy: 1) * 12)
                default:
                    break
                }
                
                if let range = Range(match.range, in: text) {
                    text.removeSubrange(range)
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
            cleanOriginalText = cleanOriginalText.replacingOccurrences(of: "\\b\(typo)\\b", with: fix, options: [.regularExpression, .caseInsensitive])
        }
        
        for (word, number) in ordinalFixes {
            cleanOriginalText = cleanOriginalText.replacingOccurrences(of: "\\b\(word)\\b", with: number, options: [.regularExpression, .caseInsensitive])
        }
        
        // Hide "due" with a zero-width space to prevent NSDataDetector from incorrectly interpreting it as "today"
        if let dueRegex = try? NSRegularExpression(pattern: "\\b(d)(ue)\\b", options: [.caseInsensitive]) {
            let range = NSRange(location: 0, length: cleanOriginalText.utf16.count)
            cleanOriginalText = dueRegex.stringByReplacingMatches(in: cleanOriginalText, options: [], range: range, withTemplate: "$1\u{200B}$2")
        }
        
        extractedDate = extractRelativeDate(text: &cleanOriginalText)
        
        let types: NSTextCheckingResult.CheckingType = [.date, .link]
        if let detector = try? NSDataDetector(types: types.rawValue) {
            let matches = detector.matches(in: cleanOriginalText, options: [], range: NSRange(location: 0, length: cleanOriginalText.utf16.count))
            
            var finalComponents = DateComponents()
            var hasExplicitDate = false
            var hasExplicitTime = false
            let todayComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            
            // First pass: Extract date components (forward to prioritize earlier and merge) and find first link
            for match in matches {
                if match.resultType == .date {
                    if extractedDate == nil, let date = match.date {
                        if let range = Range(match.range, in: cleanOriginalText) {
                            let matchedText = String(cleanOriginalText[range]).lowercased()
                            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
                            
                            let isToday = comps.year == todayComponents.year && comps.month == todayComponents.month && comps.day == todayComponents.day
                            let isNoon = comps.hour == 12 && comps.minute == 0 && comps.second == 0
                            
                            let explicitlyMentioned12 = matchedText.range(of: "(?i)(\\b12\\s*(pm|p\\.m\\.|am|a\\.m\\.)\\b|\\b12:00\\b|\\bnoon\\b|\\bat\\s+12\\b)", options: .regularExpression) != nil
                            let explicitlyMentionedToday = matchedText.range(of: "(?i)\\btoday\\b", options: .regularExpression) != nil
                            
                            if !hasExplicitDate {
                                if !isToday || explicitlyMentionedToday {
                                    finalComponents.year = comps.year
                                    finalComponents.month = comps.month
                                    finalComponents.day = comps.day
                                    hasExplicitDate = true
                                } else if finalComponents.year == nil {
                                    finalComponents.year = comps.year
                                    finalComponents.month = comps.month
                                    finalComponents.day = comps.day
                                }
                            }
                            
                            if !hasExplicitTime {
                                if !isNoon || explicitlyMentioned12 {
                                    finalComponents.hour = comps.hour
                                    finalComponents.minute = comps.minute
                                    finalComponents.second = comps.second
                                    hasExplicitTime = true
                                } else if finalComponents.hour == nil {
                                    finalComponents.hour = 7
                                    finalComponents.minute = 0
                                    finalComponents.second = 0
                                }
                            }
                        }
                    }
                } else if match.resultType == .link {
                    if extractedURL == nil {
                        extractedURL = match.url
                    }
                }
            }
            
            if extractedDate == nil && finalComponents.year != nil {
                extractedDate = Calendar.current.date(from: finalComponents)
            }
            
            // Second pass: Remove parsed dates from the string (must iterate backwards to preserve ranges)
            for match in matches.reversed() {
                if match.resultType == .date {
                    if let range = Range(match.range, in: cleanOriginalText) {
                        cleanOriginalText.removeSubrange(range)
                    }
                }
            }
        }
        
        // Remove trailing prepositions like "at", "on", "for", "in" which might have been left behind before the date
        cleanOriginalText = cleanOriginalText.replacingOccurrences(of: "(?i)\\s+(expires|due|at|on|for|in|by|until)\\s*$", with: "", options: .regularExpression)
        
        // Clean up leftover words in parentheses if they are just prepositions/keywords now
        cleanOriginalText = cleanOriginalText.replacingOccurrences(of: "(?i)\\(\\s*(expires|due|on|at|by|until|for|in)\\s*\\)", with: "()", options: .regularExpression)
        
        // Remove empty parentheses/brackets that might have been left after removing the date
        cleanOriginalText = cleanOriginalText.replacingOccurrences(of: "\\(\\s*\\)", with: "", options: .regularExpression)
        cleanOriginalText = cleanOriginalText.replacingOccurrences(of: "\\[\\s*\\]", with: "", options: .regularExpression)
        
        // Remove trailing punctuation like colons, dashes, commas
        cleanOriginalText = cleanOriginalText.replacingOccurrences(of: "[:\\-,\\s]+$", with: "", options: .regularExpression)
        
        cleanOriginalText = cleanOriginalText.replacingOccurrences(of: "\u{200B}", with: "")
        
        // Sanitize the original text to be the title
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
