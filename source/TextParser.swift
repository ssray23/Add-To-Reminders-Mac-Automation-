import Foundation
import EventKit

struct ParsedReminderData {
    let title: String
    let date: Date?
    let allDetectedDates: [Date]
    let url: URL?
    let recurrence: EKRecurrenceRule?
}

class TextParser {
    static func endOfDay(for date: Date) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = 23
        components.minute = 59
        components.second = 59
        return Calendar.current.date(from: components) ?? date
    }

    static func extractRecurrence(text: inout String) -> EKRecurrenceRule? {
        var matchedFrequency: EKRecurrenceFrequency?
        var matchedInterval: Int = 1
        var matchRangeToRemove: Range<String.Index>?
        
        let dynamicPattern = "(?i)\\b(?:repeat\\s+)?every\\s+(\\d+)\\s+(day|week|month|year)s?\\b"
        if let regex = try? NSRegularExpression(pattern: dynamicPattern, options: []) {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = regex.firstMatch(in: text, options: [], range: nsRange) {
                if let range = Range(match.range, in: text),
                   let numRange = Range(match.range(at: 1), in: text),
                   let unitRange = Range(match.range(at: 2), in: text) {
                    
                    let num = Int(String(text[numRange])) ?? 1
                    let unit = String(text[unitRange]).lowercased()
                    
                    matchRangeToRemove = range
                    matchedInterval = num
                    switch unit {
                    case "day": matchedFrequency = .daily
                    case "week": matchedFrequency = .weekly
                    case "month": matchedFrequency = .monthly
                    case "year": matchedFrequency = .yearly
                    default: matchedFrequency = .daily
                    }
                }
            }
        }
        
        if matchedFrequency == nil {
            let patterns: [(regex: String, frequency: EKRecurrenceFrequency, interval: Int)] = [
                ("(?i)\\b(?:repeat\\s+)?every\\s*other\\s*day\\b", .daily, 2),
                ("(?i)\\b(?:repeat\\s+)?every\\s*other\\s*week\\b", .weekly, 2),
                ("(?i)\\b(?:repeat\\s+)?every\\s*other\\s*month\\b", .monthly, 2),
                ("(?i)\\b(?:repeat\\s+)?every\\s*other\\s*year\\b", .yearly, 2),
                ("(?i)\\b(?:repeat\\s+)?(every\\s*day|daily)\\b", .daily, 1),
                ("(?i)\\b(?:repeat\\s+)?(every\\s*week|weekly)\\b", .weekly, 1),
                ("(?i)\\b(?:repeat\\s+)?(every\\s*month|monthly)\\b", .monthly, 1),
                ("(?i)\\b(?:repeat\\s+)?(every\\s*year|yearly)\\b", .yearly, 1),
                ("(?i)\\b(repeat)\\b(?=\\s+(?:for|until|ending|ends))", .daily, 1)
            ]
            
            for item in patterns {
                if let regex = try? NSRegularExpression(pattern: item.regex, options: []) {
                    let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
                    if let match = regex.firstMatch(in: text, options: [], range: nsRange) {
                        if let range = Range(match.range, in: text) {
                            matchRangeToRemove = range
                            matchedFrequency = item.frequency
                            matchedInterval = item.interval
                            break
                        }
                    }
                }
            }
        }
        
        guard let freq = matchedFrequency, let removeRange = matchRangeToRemove else {
            return nil
        }
        
        text.removeSubrange(removeRange)
        
        var recurrenceEnd: EKRecurrenceEnd? = nil
        let untilRegex = try? NSRegularExpression(pattern: "(?i)\\b(until|ending\\s+on|ends\\s+on|for\\s*(?:the\\s*)?next|for)\\b", options: [])
        if let untilRegex = untilRegex,
           let untilMatch = untilRegex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text)) {
            
            let substringRange = NSRange(location: untilMatch.range.upperBound, length: text.utf16.count - untilMatch.range.upperBound)
            
            if let relativeData = extractRelativeDate(text: text, searchRange: substringRange) {
                recurrenceEnd = EKRecurrenceEnd(end: endOfDay(for: relativeData.0))
                
                let removeNSRange = NSRange(location: untilMatch.range.lowerBound, length: relativeData.1.upperBound - untilMatch.range.lowerBound)
                if let removeRange = Range(removeNSRange, in: text) {
                    text.removeSubrange(removeRange)
                }
            } else if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
               let dateMatch = detector.firstMatch(in: text, options: [], range: substringRange),
               let parsedDate = dateMatch.date {
                
                recurrenceEnd = EKRecurrenceEnd(end: endOfDay(for: parsedDate))
                
                let removeNSRange = NSRange(location: untilMatch.range.lowerBound, length: dateMatch.range.upperBound - untilMatch.range.lowerBound)
                if let removeRange = Range(removeNSRange, in: text) {
                    text.removeSubrange(removeRange)
                }
            }
        }
        
        return EKRecurrenceRule(recurrenceWith: freq, interval: matchedInterval, end: recurrenceEnd)
    }

    static func extractRelativeDate(text: String, searchRange: NSRange? = nil) -> (Date, NSRange, Bool)? {
        let units = "m|min|mins|minute|minutes|h|hr|hrs|hour|hours|d|day|days|w|wk|wks|week|weeks|mo|mos|month|months|y|yr|yrs|year|years"
        let pattern = "(?i)(?:\\bin\\s+(\\d+(?:[.,]\\d+)?)\\s*(\(units))\\b|\\b(\\d+(?:[.,]\\d+)?)\\s*(\(units))\\b\\s+from\\s+now)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        
        let nsRange = searchRange ?? NSRange(text.startIndex..<text.endIndex, in: text)
        if let match = regex.firstMatch(in: text, options: [], range: nsRange) {
            let valRange = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 3)
            let unRange = match.range(at: 2).location != NSNotFound ? match.range(at: 2) : match.range(at: 4)
            
            if let valueRange = Range(valRange, in: text),
               let unitRange = Range(unRange, in: text) {
                
                let valueString = String(text[valueRange]).replacingOccurrences(of: ",", with: ".")
                guard let value = Double(valueString) else { return nil }
                
                let unitString = String(text[unitRange]).lowercased()
                var component = DateComponents()
                var isDateOnly = false
                
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
                    isDateOnly = (component.hour == 0)
                case "w", "wk", "wks", "week", "weeks":
                    component.day = Int(value) * 7
                    component.hour = Int(value.truncatingRemainder(dividingBy: 1) * 24 * 7)
                    isDateOnly = (component.hour == 0)
                case "mo", "mos", "month", "months":
                    component.month = Int(value)
                    component.day = Int(value.truncatingRemainder(dividingBy: 1) * 30)
                    isDateOnly = (component.day == 0)
                case "y", "yr", "yrs", "year", "years":
                    component.year = Int(value)
                    component.month = Int(value.truncatingRemainder(dividingBy: 1) * 12)
                    isDateOnly = (component.month == 0)
                default:
                    break
                }
                
                let date = Calendar.current.date(byAdding: component, to: Date())!
                return (date, match.range, isDateOnly)
            }
        }
        return nil
    }

    static func parse(text: String) -> ParsedReminderData {
        var allDetectedDates: [Date] = []
        var extractedDate: Date? = nil
        var extractedURL: URL? = nil
        
        var cleanOriginalText = text
        
        // Pre-process specifically for the date detector to handle common typos
        let typoFixes = [
            "tommorow": "tomorrow",
            "tomorow": "tomorrow",
            "tommorrow": "tomorrow",
            "tommroow": "tomorrow",
            "tomrrow": "tomorrow",
            "tomoro": "tomorrow",
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
            "hra": "hrs",
            "evry": "every",
            "wek": "week",
            "mounth": "month"
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
        
        let recurrenceRule = extractRecurrence(text: &cleanOriginalText)
        
        // Hide tricky words with a zero-width space to prevent NSDataDetector from incorrectly interpreting them as durations starting today
        let trickyWords = ["due", "before", "by", "until"]
        for word in trickyWords {
            let prefix = String(word.prefix(1))
            let suffix = String(word.dropFirst())
            if let regex = try? NSRegularExpression(pattern: "\\b(\(prefix))(\(suffix))\\b", options: [.caseInsensitive]) {
                let range = NSRange(location: 0, length: cleanOriginalText.utf16.count)
                cleanOriginalText = regex.stringByReplacingMatches(in: cleanOriginalText, options: [], range: range, withTemplate: "$1\u{200B}$2")
            }
        }
        
        var extractedRelativeComponents: [(DateComponents, NSRange)] = []
        
        while let relativeData = extractRelativeDate(text: cleanOriginalText) {
            let date = relativeData.0
            let matchedNSRange = relativeData.1
            let isDateOnly = relativeData.2
            
            var comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            if isDateOnly {
                comps.hour = nil
                comps.minute = nil
                comps.second = nil
            }
            
            extractedRelativeComponents.append((comps, matchedNSRange))
            
            if let range = Range(matchedNSRange, in: cleanOriginalText) {
                // Replace with spaces to preserve ranges for NSDataDetector
                let replacement = String(repeating: " ", count: cleanOriginalText.distance(from: range.lowerBound, to: range.upperBound))
                cleanOriginalText.replaceSubrange(range, with: replacement)
            }
        }
        
        let types: NSTextCheckingResult.CheckingType = [.date, .link]
        if let detector = try? NSDataDetector(types: types.rawValue) {
            let matches = detector.matches(in: cleanOriginalText, options: [], range: NSRange(location: 0, length: cleanOriginalText.utf16.count))
            
            let todayComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            
            // First pass: Extract date components (forward to prioritize earlier and merge) and find first link
            var dateComponentsGroupsWithRange: [(DateComponents, NSRange)] = []
            dateComponentsGroupsWithRange.append(contentsOf: extractedRelativeComponents)
            
            for match in matches {
                if match.resultType == .date {
                    if let date = match.date {
                        if let range = Range(match.range, in: cleanOriginalText) {
                            let matchedText = String(cleanOriginalText[range]).lowercased()
                            var comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
                            
                            let isToday = comps.year == todayComponents.year && comps.month == todayComponents.month && comps.day == todayComponents.day
                            let isNoon = comps.hour == 12 && comps.minute == 0 && comps.second == 0
                            
                            let explicitlyMentioned12 = matchedText.range(of: "(?i)(\\b12\\s*(pm|p\\.m\\.|am|a\\.m\\.)\\b|\\b12:00\\b|\\bnoon\\b|\\bat\\s+12\\b)", options: .regularExpression) != nil
                            let explicitlyMentionedToday = matchedText.range(of: "(?i)\\btoday\\b", options: .regularExpression) != nil
                            
                            if isToday && !explicitlyMentionedToday {
                                comps.year = nil
                                comps.month = nil
                                comps.day = nil
                            }
                            
                            if isNoon && !explicitlyMentioned12 {
                                comps.hour = nil
                                comps.minute = nil
                                comps.second = nil
                            }
                            
                            dateComponentsGroupsWithRange.append((comps, match.range))
                        }
                    }
                } else if match.resultType == .link {
                    if extractedURL == nil {
                        extractedURL = match.url
                    }
                }
            }
            
            // Sort components by their position in the string
            dateComponentsGroupsWithRange.sort { $0.1.location < $1.1.location }
            
            // Now resolve date groups. Usually they might be separate matches like "August 12" and "at 5pm" or separate dates entirely.
            var currentMergedComponents = DateComponents()
            for groupData in dateComponentsGroupsWithRange {
                let group = groupData.0
                let hasDateParts = group.year != nil || group.month != nil || group.day != nil
                let hasTimeParts = group.hour != nil || group.minute != nil
                
                let currentHasDate = currentMergedComponents.year != nil || currentMergedComponents.month != nil || currentMergedComponents.day != nil
                let currentHasTime = currentMergedComponents.hour != nil || currentMergedComponents.minute != nil
                
                if (hasDateParts && currentHasDate) || (hasTimeParts && currentHasTime) {
                    // This is a separate date, let's flush current
                    if currentHasDate {
                        if currentMergedComponents.hour == nil {
                            currentMergedComponents.hour = 7
                            currentMergedComponents.minute = 0
                            currentMergedComponents.second = 0
                        }
                        if let d = Calendar.current.date(from: currentMergedComponents) {
                            allDetectedDates.append(d)
                        }
                    }
                    currentMergedComponents = group
                } else {
                    if hasDateParts {
                        currentMergedComponents.year = group.year
                        currentMergedComponents.month = group.month
                        currentMergedComponents.day = group.day
                    }
                    if hasTimeParts {
                        currentMergedComponents.hour = group.hour
                        currentMergedComponents.minute = group.minute
                        currentMergedComponents.second = group.second
                    }
                }
            }
            
            // Flush the last one
            if currentMergedComponents.year != nil || currentMergedComponents.month != nil || currentMergedComponents.day != nil {
                if currentMergedComponents.hour == nil {
                    currentMergedComponents.hour = 7
                    currentMergedComponents.minute = 0
                    currentMergedComponents.second = 0
                }
                if let d = Calendar.current.date(from: currentMergedComponents) {
                    allDetectedDates.append(d)
                }
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
        
        cleanOriginalText = cleanOriginalText.replacingOccurrences(of: "\u{200B}", with: "")
        
        // Remove trailing prepositions like "at", "on", "for", "in" which might have been left behind before the date
        cleanOriginalText = cleanOriginalText.replacingOccurrences(of: "(?i)\\s+(expires|due|before|at|on|for|in|by|until)\\s*$", with: "", options: .regularExpression)
        
        // Clean up leftover words in parentheses if they are just prepositions/keywords now
        cleanOriginalText = cleanOriginalText.replacingOccurrences(of: "(?i)\\(\\s*(expires|due|before|on|at|by|until|for|in)\\s*\\)", with: "()", options: .regularExpression)
        
        // Remove empty parentheses/brackets that might have been left after removing the date
        cleanOriginalText = cleanOriginalText.replacingOccurrences(of: "\\(\\s*\\)", with: "", options: .regularExpression)
        cleanOriginalText = cleanOriginalText.replacingOccurrences(of: "\\[\\s*\\]", with: "", options: .regularExpression)
        
        // Remove trailing punctuation like colons, dashes, commas
        cleanOriginalText = cleanOriginalText.replacingOccurrences(of: "[:\\-,\\s]+$", with: "", options: .regularExpression)
        
        // Sanitize the original text to be the title
        let components = cleanOriginalText.components(separatedBy: .whitespacesAndNewlines)
        var finalTitle = components.filter { !$0.isEmpty }.joined(separator: " ")
        
        // Remove leading punctuation like commas or dashes if they are somehow present,
        // though trimming whitespaces above is usually enough. 
        if finalTitle.isEmpty {
            finalTitle = "New Reminder"
        }
        
        if !allDetectedDates.isEmpty {
            extractedDate = allDetectedDates.first
        }
        
        return ParsedReminderData(title: finalTitle, date: extractedDate, allDetectedDates: allDetectedDates, url: extractedURL, recurrence: recurrenceRule)
    }
}
