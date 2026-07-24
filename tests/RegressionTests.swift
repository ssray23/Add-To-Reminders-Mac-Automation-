import Foundation
import EventKit

@main
struct RegressionTests {
    static var testsPassed = 0
    static var testsFailed = 0

    // Known-bug lane: tracked separately so unfixed, already-identified bugs
    // don't mask new regressions in the main suite's exit code.
    static var knownBugsFixed = 0
    static var knownBugsStillOpen = 0

    static func assertTest(_ name: String, _ condition: Bool, _ details: String = "") {
        if condition {
            testsPassed += 1
            print("  ✅ [PASS] \(name)")
        } else {
            testsFailed += 1
            print("  ❌ [FAIL] \(name) - \(details)")
        }
    }

    // Use for bugs already identified and not yet patched. If it starts
    // passing, that's a signal the fix landed, promote it to assertTest.
    static func assertKnownBug(_ name: String, _ condition: Bool, _ details: String = "") {
        if condition {
            knownBugsFixed += 1
            print("  ✅ [FIXED] \(name)")
        } else {
            knownBugsStillOpen += 1
            print("  ⚠️  [KNOWN BUG] \(name) - \(details)")
        }
    }

    static func assertRecurrenceDetails(_ name: String, _ rule: EKRecurrenceRule?, frequency: EKRecurrenceFrequency, interval: Int) {
        guard let rule = rule else {
            assertTest(name, false, "Recurrence was nil")
            return
        }
        let ok = rule.frequency == frequency && rule.interval == interval
        assertTest(name, ok, "Expected freq=\(frequency) interval=\(interval), got freq=\(rule.frequency) interval=\(rule.interval)")
    }

    static func main() {
        print("==================================================")
        print("         RUNNING TEXTPARSER REGRESSION SUITE       ")
        print("==================================================")

        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        // 1. Relative duration tests (Hours & Minutes)
        print("\n--- 1. Relative Duration Tests ---")
        let r1 = TextParser.parse(text: "Koreaverse Recharge in 2 hours")
        assertTest("Relative 'in 2 hours' title", r1.title == "Koreaverse Recharge", "Got '\(r1.title)'")
        if let d = r1.date {
            let expectedHour = calendar.component(.hour, from: Date().addingTimeInterval(7200))
            let actualHour = calendar.component(.hour, from: d)
            assertTest("Relative 'in 2 hours' hour (\(actualHour))", actualHour == expectedHour, "Expected hour \(expectedHour), got \(actualHour)")
        } else {
            assertTest("Relative 'in 2 hours' date exists", false, "Date was nil")
        }

        let r2 = TextParser.parse(text: "Remind me in 30 mins")
        assertTest("Relative 'in 30 mins' title", r2.title == "Remind me", "Got '\(r2.title)'")
        if let d = r2.date {
            let diff = abs(d.timeIntervalSince(Date().addingTimeInterval(1800)))
            assertTest("Relative 'in 30 mins' time offset", diff < 120, "Time diff too large: \(diff)s")
        } else {
            assertTest("Relative 'in 30 mins' date exists", false, "Date was nil")
        }

        let r3 = TextParser.parse(text: "Call Mom in 6 hrs")
        assertTest("Relative 'in 6 hrs' title", r3.title == "Call Mom", "Got '\(r3.title)'")
        if let d = r3.date {
            let actualHour = calendar.component(.hour, from: d)
            let expectedHour = calendar.component(.hour, from: Date().addingTimeInterval(21600))
            assertTest("Relative 'in 6 hrs' hour (\(actualHour))", actualHour == expectedHour, "Expected \(expectedHour), got \(actualHour)")
        } else {
            assertTest("Relative 'in 6 hrs' date exists", false, "Date was nil")
        }

        // 2. Relative Duration Ranges
        print("\n--- 2. Relative Duration Ranges ---")
        let r4 = TextParser.parse(text: "Call Mom in 6 hrs or 8 hrs")
        assertTest("Multi-duration date count (2)", r4.allDetectedDates.count == 2, "Got \(r4.allDetectedDates.count) dates")

        // 3. Date-Only Durations (Default 7:00 AM)
        print("\n--- 3. Date-Only Durations (Default 7:00 AM) ---")
        let r5 = TextParser.parse(text: "Buy groceries in 3 days")
        assertTest("Relative 'in 3 days' title", r5.title == "Buy groceries", "Got '\(r5.title)'")
        if let d = r5.date {
            let hour = calendar.component(.hour, from: d)
            let min = calendar.component(.minute, from: d)
            assertTest("Relative 'in 3 days' defaults to 7:00 AM", hour == 7 && min == 0, "Got \(hour):\(min)")
        } else {
            assertTest("Relative 'in 3 days' date exists", false, "Date was nil")
        }

        // 4. Absolute Times & Typo Fixes
        print("\n--- 4. Absolute Times & Typo Fixes ---")
        let r6 = TextParser.parse(text: "Meeting tommorow at 3pm")
        assertTest("Typo 'tommorow' + '3pm' title", r6.title == "Meeting", "Got '\(r6.title)'")
        if let d = r6.date {
            let hour = calendar.component(.hour, from: d)
            assertTest("3pm maps to 15:00", hour == 15, "Got hour \(hour)")
        } else {
            assertTest("Typo 'tommorow' date exists", false, "Date was nil")
        }

        let r7 = TextParser.parse(text: "Workout tmrw")
        assertTest("Typo 'tmrw' title", r7.title == "Workout", "Got '\(r7.title)'")
        if let d = r7.date {
            let hour = calendar.component(.hour, from: d)
            assertTest("'tmrw' without time defaults to 7:00 AM", hour == 7, "Got hour \(hour)")
        } else {
            assertTest("Typo 'tmrw' date exists", false, "Date was nil")
        }

        // 5. Tricky Words (due, before, by, until)
        print("\n--- 5. Tricky Words Handling ---")
        let r8 = TextParser.parse(text: "Project due tomorrow")
        assertTest("Tricky word 'due' title", r8.title == "Project", "Got '\(r8.title)'")

        let r9 = TextParser.parse(text: "Report before Friday")
        assertTest("Tricky word 'before' title", r9.title == "Report", "Got '\(r9.title)'")

        // 6. Weekend Phrase Parsing
        print("\n--- 6. Weekend Phrase Parsing ---")
        let r10 = TextParser.parse(text: "Do laundry this weekend")
        assertTest("Weekend generates 2 candidate dates (Sat & Sun)", r10.allDetectedDates.count == 2, "Got \(r10.allDetectedDates.count)")
        if let d = r10.date {
            let hour = calendar.component(.hour, from: d)
            assertTest("Weekend default time is 7:00 AM", hour == 7, "Got hour \(hour)")
        }

        let r11 = TextParser.parse(text: "Do laundry this weekend at 2pm")
        if let d = r11.date {
            let hour = calendar.component(.hour, from: d)
            assertTest("Weekend with 'at 2pm' sets 14:00", hour == 14, "Got hour \(hour)")
        } else {
            assertTest("Weekend 'at 2pm' date exists", false, "Date was nil")
        }

        // 7. URL Extraction
        print("\n--- 7. URL Extraction ---")
        let r12 = TextParser.parse(text: "Read article https://apple.com tomorrow")
        assertTest("URL parsed correctly", r12.url?.absoluteString == "https://apple.com", "Got '\(r12.url?.absoluteString ?? "nil")'")
        assertTest("URL stripped from title", r12.title == "Read article", "Got '\(r12.title)'")

        // 8. Recurrence Parsing
        print("\n--- 8. Recurrence Parsing ---")
        let r13 = TextParser.parse(text: "Water plants every day")
        assertTest("Recurrence rule extracted", r13.recurrence != nil, "Recurrence was nil")
        assertTest("Recurrence title clean", r13.title == "Water plants", "Got '\(r13.title)'")

        // 9. Date Range Parsing (Daily Recurrence)
        print("\n--- 9. Date Range Parsing ---")
        let r14 = TextParser.parse(text: "Chick’n’Rice with a FREE side of Pepe's Chilli Cheese Nuggets 20-26 july")
        assertTest("Date range title clean", r14.title == "Chick’n’Rice with a FREE side of Pepe's Chilli Cheese Nuggets", "Got '\(r14.title)'")
        assertTest("Date range recurrence exists", r14.recurrence != nil, "Recurrence was nil")
        if let d = r14.date {
            let day = calendar.component(.day, from: d)
            let month = calendar.component(.month, from: d)
            assertTest("Date range start date is July 20", day == 20 && month == 7, "Got day \(day), month \(month)")
        } else {
            assertTest("Date range start date exists", false, "Date was nil")
        }
        if let end = r14.recurrence?.recurrenceEnd?.endDate {
            let endDay = calendar.component(.day, from: end)
            let endMonth = calendar.component(.month, from: end)
            assertTest("Date range end date is July 26", endDay == 26 && endMonth == 7, "Got end day \(endDay), month \(endMonth)")
        } else {
            assertTest("Date range recurrence end date exists", false, "End date was nil")
        }

        let r15 = TextParser.parse(text: "Chick’n’Rice with a FREE side of Pepe's Chilli Cheese Nuggets, available exclusively this week (20-26 July)")
        assertTest("Date range in parens title clean", r15.title == "Chick’n’Rice with a FREE side of Pepe's Chilli Cheese Nuggets, available exclusively this week", "Got '\(r15.title)'")
        assertTest("Date range in parens recurrence exists", r15.recurrence != nil, "Recurrence was nil")

        let r16 = TextParser.parse(text: "Workout 20th - 26th July at 8am")
        assertTest("Date range with explicit time title clean", r16.title == "Workout", "Got '\(r16.title)'")
        if let d = r16.date {
            let hour = calendar.component(.hour, from: d)
            assertTest("Date range with 8am sets hour 8", hour == 8, "Got hour \(hour)")
        }

        let r17 = TextParser.parse(text: "Event July 20-26")
        assertTest("Month-first date range title clean", r17.title == "Event", "Got '\(r17.title)'")
        assertTest("Month-first date range recurrence exists", r17.recurrence != nil, "Recurrence was nil")

        let r18 = TextParser.parse(text: "Festival 28 July - 3 August")
        assertTest("Cross-month date range title clean", r18.title == "Festival", "Got '\(r18.title)'")
        if let end = r18.recurrence?.recurrenceEnd?.endDate {
            let endDay = calendar.component(.day, from: end)
            let endMonth = calendar.component(.month, from: end)
            assertTest("Cross-month date range end is Aug 3", endDay == 3 && endMonth == 8, "Got end day \(endDay), month \(endMonth)")
        }

        let r19 = TextParser.parse(text: "Meeting 20/07 - 26/07")
        assertTest("Numeric date range title clean", r19.title == "Meeting", "Got '\(r19.title)'")
        assertTest("Numeric date range recurrence exists", r19.recurrence != nil, "Recurrence was nil")

        // 10. KNOWN BUG REGRESSIONS - name & bare-number corruption
        print("\n--- 10. KNOWN BUG REGRESSIONS (Name / Bare Number Corruption) ---")
        print("  These document bugs found in code review. Tracked separately from")
        print("  the main suite so they don't mask new regressions while unfixed.")

        let b1 = TextParser.parse(text: "Call Tony about the invoice")
        assertKnownBug("Name 'Tony' preserved (not rewritten to 'today')", b1.title == "Call Tony about the invoice", "Got '\(b1.title)' — caused by typoFixes['tony'] = 'today'")

        let b2 = TextParser.parse(text: "Buy 12 eggs")
        assertKnownBug("Bare number '12' preserved in title", b2.title == "Buy 12 eggs", "Got '\(b2.title)' — caused by overly-greedy time-strip regex")

        let b3 = TextParser.parse(text: "iOS 18 release notes")
        assertKnownBug("Bare number '18' preserved in title", b3.title == "iOS 18 release notes", "Got '\(b3.title)' — same time-strip regex bug")

        let b4 = TextParser.parse(text: "Room 12 booking confirmed")
        assertKnownBug("Bare number mid-sentence preserved", b4.title == "Room 12 booking confirmed", "Got '\(b4.title)' — same time-strip regex bug")

        // 11. Recurrence Frequency & Interval Coverage
        print("\n--- 11. Recurrence Frequency & Interval Coverage ---")
        let r20 = TextParser.parse(text: "Pay rent every month")
        assertTest("'every month' title clean", r20.title == "Pay rent", "Got '\(r20.title)'")
        assertRecurrenceDetails("'every month' -> monthly, interval 1", r20.recurrence, frequency: .monthly, interval: 1)

        let r21 = TextParser.parse(text: "Renew passport every year")
        assertTest("'every year' title clean", r21.title == "Renew passport", "Got '\(r21.title)'")
        assertRecurrenceDetails("'every year' -> yearly, interval 1", r21.recurrence, frequency: .yearly, interval: 1)

        let r22 = TextParser.parse(text: "Water plants weekly")
        assertRecurrenceDetails("'weekly' keyword -> weekly, interval 1", r22.recurrence, frequency: .weekly, interval: 1)

        let r23 = TextParser.parse(text: "Take out bins every 2 weeks")
        assertTest("'every 2 weeks' title clean", r23.title == "Take out bins", "Got '\(r23.title)'")
        assertRecurrenceDetails("'every 2 weeks' -> weekly, interval 2", r23.recurrence, frequency: .weekly, interval: 2)

        let r24 = TextParser.parse(text: "Deep clean every 3 months")
        assertRecurrenceDetails("'every 3 months' -> monthly, interval 3", r24.recurrence, frequency: .monthly, interval: 3)

        // 12. "Every Other" Interval Shorthand
        print("\n--- 12. 'Every Other' Interval Shorthand ---")
        let r25 = TextParser.parse(text: "Bin collection every other day")
        assertRecurrenceDetails("'every other day' -> daily, interval 2", r25.recurrence, frequency: .daily, interval: 2)

        let r26 = TextParser.parse(text: "Team sync every other week")
        assertRecurrenceDetails("'every other week' -> weekly, interval 2", r26.recurrence, frequency: .weekly, interval: 2)

        // 13. Weekday / Weekend Recurrence Day-of-Week
        print("\n--- 13. Weekday / Weekend Recurrence Day-of-Week ---")
        let r27 = TextParser.parse(text: "Take vitamins on weekdays")
        assertTest("'weekdays' title clean", r27.title == "Take vitamins", "Got '\(r27.title)'")
        if let days = r27.recurrence?.daysOfTheWeek {
            assertTest("'weekdays' produces 5 days", days.count == 5, "Got \(days.count) days")
        } else {
            assertTest("'weekdays' daysOfTheWeek exists", false, "daysOfTheWeek was nil")
        }

        let r28 = TextParser.parse(text: "Sleep in on weekends")
        if let days = r28.recurrence?.daysOfTheWeek {
            assertTest("'weekends' produces 2 days", days.count == 2, "Got \(days.count) days")
        } else {
            assertTest("'weekends' daysOfTheWeek exists", false, "daysOfTheWeek was nil")
        }

        // 14. Fixed-Duration Recurrence ("for X days")
        print("\n--- 14. Fixed-Duration Recurrence ('for X days') ---")
        let r29 = TextParser.parse(text: "Take antibiotics for 7 days")
        assertTest("'for 7 days' title clean", r29.title == "Take antibiotics", "Got '\(r29.title)'")
        assertTest("'for 7 days' recurrence exists", r29.recurrence != nil, "Recurrence was nil")
        if let end = r29.recurrence?.recurrenceEnd?.endDate {
            let expected = calendar.date(byAdding: .day, value: 7, to: Date())!
            assertTest("'for 7 days' end date is ~7 days out", calendar.isDate(end, inSameDayAs: expected), "Got \(formatter.string(from: end))")
        } else {
            assertTest("'for 7 days' recurrenceEnd exists", false, "recurrenceEnd was nil")
        }

        // 15. "Until <date>" Trailing Recurrence End
        print("\n--- 15. 'Until <date>' Trailing Recurrence End ---")
        let r30 = TextParser.parse(text: "Take medicine daily until next Friday")
        assertTest("'daily until next Friday' title clean", r30.title == "Take medicine", "Got '\(r30.title)'")
        assertRecurrenceDetails("'daily until next Friday' -> daily, interval 1", r30.recurrence, frequency: .daily, interval: 1)
        assertTest("'daily until next Friday' has an end date", r30.recurrence?.recurrenceEnd?.endDate != nil, "recurrenceEnd was nil")

        // This one specifically targets the buggy FIRST "until" branch in
        // extractRecurrence (the one that assumes the date starts at
        // dateStr's position 0). Padding text between "until" and the date
        // should not corrupt the title or silently drop the recurrence.
        let r30b = TextParser.parse(text: "Follow up until sometime next Friday")
        assertKnownBug("'until sometime next Friday' title not mangled", r30b.title == "Follow up", "Got '\(r30b.title)' — likely the mis-anchored range-removal bug in the first 'until' branch")

        // 16. Feedback Message Frequency Label
        print("\n--- 16. Feedback Message Frequency Label ---")
        let r31 = TextParser.parse(text: "Pay rent every month")
        if let msg = TextParser.formatParsedDateFeedback(r31) {
            assertKnownBug("Monthly recurrence feedback doesn't say 'Repeats daily'", !msg.contains("Repeats daily"), "Got '\(msg)' — formatParsedDateFeedback hardcodes 'Repeats daily' for any rule")
        } else {
            assertTest("Monthly recurrence feedback exists", false, "formatParsedDateFeedback returned nil")
        }

        // 17. Ordinal Word Conversion
        print("\n--- 17. Ordinal Word Conversion ---")
        let r32 = TextParser.parse(text: "Submit report on the third of August")
        assertTest("'third' converts and parses to a date", r32.date != nil, "Date was nil")
        if let d = r32.date {
            let day = calendar.component(.day, from: d)
            let month = calendar.component(.month, from: d)
            assertTest("Ordinal date is Aug 3", day == 3 && month == 8, "Got day \(day), month \(month)")
        }

        // 18. Empty / Whitespace-Only Title Fallback
        print("\n--- 18. Empty / Whitespace-Only Title Fallback ---")
        let r33 = TextParser.parse(text: "tomorrow")
        assertTest("Pure date input falls back to 'New Reminder'", r33.title == "New Reminder", "Got '\(r33.title)'")

        let r34 = TextParser.parse(text: "   ")
        assertTest("Whitespace-only input falls back to 'New Reminder'", r34.title == "New Reminder", "Got '\(r34.title)'")

        // 19. No Date Present
        print("\n--- 19. No Date Present ---")
        let r35 = TextParser.parse(text: "Buy milk")
        assertTest("No date -> title unchanged", r35.title == "Buy milk", "Got '\(r35.title)'")
        assertTest("No date -> date is nil", r35.date == nil, "Expected nil, got \(String(describing: r35.date))")
        assertTest("No date -> recurrence is nil", r35.recurrence == nil, "Expected non-nil to be nil")

        // 20. Past-Date Rollover (Year Bump)
        print("\n--- 20. Past-Date Rollover (Year Bump) ---")
        // createRangeDate rolls a dateless year forward if the resulting date
        // is more than 6 months in the past relative to today. Confirms that
        // logic actually fires rather than silently returning a past date.
        let r36 = TextParser.parse(text: "Ski trip 10-15 January")
        assertTest("Past month-range still produces a date", r36.date != nil, "Date was nil")
        if let d = r36.date {
            let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: Date())!
            assertTest("Rolled-forward start date is not >6 months in the past", d > sixMonthsAgo, "Got \(formatter.string(from: d))")
        }

        // 21. Decimal Duration Values
        print("\n--- 21. Decimal Duration Values ---")
        let r37 = TextParser.parse(text: "Check oven in 1.5 hours")
        assertTest("'in 1.5 hours' title clean", r37.title == "Check oven", "Got '\(r37.title)'")
        if let d = r37.date {
            let diff = abs(d.timeIntervalSince(Date().addingTimeInterval(5400)))
            assertTest("'1.5 hours' offset ~90 min", diff < 120, "Time diff too large: \(diff)s")
        } else {
            assertTest("'1.5 hours' date exists", false, "Date was nil")
        }

        // 22. Typo Correction Combined With Recurrence
        print("\n--- 22. Typo Correction Combined With Recurrence ---")
        let r38 = TextParser.parse(text: "Backup files wkly")
        assertRecurrenceDetails("'wkly' typo -> weekly, interval 1", r38.recurrence, frequency: .weekly, interval: 1)
        assertTest("'wkly' typo title clean", r38.title == "Backup files", "Got '\(r38.title)'")

        // 23. General Name/Number Preservation Sanity
        print("\n--- 23. General Name/Number Preservation Sanity ---")
        let r39 = TextParser.parse(text: "Meet Sarah for coffee")
        assertTest("No spurious date extracted from plain name", r39.date == nil, "Expected nil, got \(String(describing: r39.date))")
        assertTest("Title unchanged", r39.title == "Meet Sarah for coffee", "Got '\(r39.title)'")

        // ============================================================
        // SUMMARY
        // ============================================================
        print("==================================================")
        print("  SUITE:       \(testsPassed) PASSED, \(testsFailed) FAILED")
        print("  KNOWN BUGS:  \(knownBugsFixed) FIXED, \(knownBugsStillOpen) STILL OPEN")
        print("==================================================")
        if knownBugsStillOpen > 0 {
            print("  ⚠️  \(knownBugsStillOpen) known bug(s) still open — see section 10, 15, 16 above.")
        }

        // Only real regressions fail the build. Known, already-tracked bugs
        // don't block CI, but they stay visible until fixed.
        if testsFailed > 0 {
            exit(1)
        }
    }
}
